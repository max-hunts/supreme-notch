//
//  AgentEventManager.swift
//  Notchly
//
//  Created by n0xbyte on 29.05.2026.
//

import Foundation
import Combine
import AppKit
import Darwin

enum AgentEventKind: String, Decodable {
    case accessRequest = "access_request"
    case clear
    case waiting
    case completed
    case failed
    case started
    case progress
    case cancelled
}

/// A permission request an agent hook is blocking on. The hook polls for a decision file.
struct AgentApprovalRequest: Identifiable, Equatable {
    let id: String
    let source: String
    let sessionID: String?
    let toolName: String
    let toolLabel: String
    let summary: String
    let detail: String?
    let project: String?
    let receivedAt: Date
    let deadline: Date
}

enum AgentApprovalDecision {
    case approve
    case deny
    case answerInTerminal
}

/// One battery in a set of headphones, for the AirPods glance rings.
nonisolated struct GlanceBatteryPart: Equatable {
    enum Kind: Equatable {
        case left
        case right
        case `case`
        case single
    }

    let kind: Kind
    let level: Int
    let isCharging: Bool
}

/// A button shown on a glance, for example Join and Dismiss on a meeting reminder.
nonisolated struct GlanceButton: Equatable, Identifiable {
    enum Action: Equatable {
        case open(URL)
        case dismiss
        /// Shows the agent session the alert came from.
        case openSession(id: String, source: String)
    }

    var id: String { title }
    let title: String
    let systemImage: String
    let isPrimary: Bool
    let action: Action
}

/// What clicking a glance does, beyond opening `actionURL`.
nonisolated enum GlanceAction: Equatable {
    case ejectVolume(URL)
    case dismiss
}

/// Visual style for non-agent glances (downloads, calendar, AirPods).
nonisolated struct AgentGlanceStyle: Equatable {
    let symbolName: String
    let red: Double
    let green: Double
    let blue: Double
}

struct AgentEvent: Identifiable, Equatable {
    let id: UUID
    let source: String
    let kind: AgentEventKind
    let title: String
    let message: String?
    let ttl: TimeInterval
    let createdAt: Date
    var approval: AgentApprovalRequest? = nil
    /// One or two lines shown under the title, such as a completion summary.
    var detail: String? = nil
    var glance: AgentGlanceStyle? = nil
    var actionURL: URL? = nil
    var action: GlanceAction? = nil
    var batteryParts: [GlanceBatteryPart] = []
    /// Key into GlanceProgressStore for a live progress ring.
    var progressKey: String? = nil
    /// Stays on screen until dismissed. Other alerts can cover it; it returns after them.
    var isSticky = false
    var buttons: [GlanceButton] = []
    /// The agent session this alert came from, so a click can open that session.
    var sessionID: String? = nil

    var sourceLabel: String {
        switch source.lowercased() {
        case "codex":
            return "Codex"
        case "claude":
            return "Claude Code"
        case "cursor":
            return "Cursor"
        case "downloads":
            return "Downloads"
        case "calendar":
            return "Calendar"
        case "airpods":
            return "AirPods"
        default:
            return source
        }
    }
}

private struct AgentEventPayload: Decodable {
    let source: String?
    let type: AgentEventKind?
    let title: String?
    let message: String?
    let ttl: TimeInterval?
    let requestID: String?
    let payloadID: String?
    let sessionID: String?
    let toolName: String?
    let hookEvent: String?
    let cwd: String?
    let step: String?
    let pid: Int?

    enum CodingKeys: String, CodingKey {
        case source, type, title, message, ttl, cwd, step, pid
        case requestID = "request_id"
        case payloadID = "payload_id"
        case sessionID = "session_id"
        case toolName = "tool_name"
        case hookEvent = "hook_event"
    }
}

@MainActor
final class AgentEventManager: ObservableObject {
    @Published private(set) var currentEvent: AgentEvent?
    @Published private(set) var eventID = 0
    @Published private(set) var pendingApprovals: [AgentApprovalRequest] = []
    let sessionTracker = AgentSessionTracker()

    private let settingsManager: SettingsManager
    private let fileManager = FileManager.default
    private var fileEventSource: DispatchSourceFileSystemObject?
    private var fallbackWatchTask: Task<Void, Never>?
    private var clearTask: Task<Void, Never>?
    private var expiryTask: Task<Void, Never>?
    private var cancellables = Set<AnyCancellable>()
    /// A sticky glance covered by another alert, shown again when that alert clears.
    private var parkedSticky: AgentEvent?
    private var readOffset: UInt64 = 0
    private var lastShownEventKey: String?
    private var lastShownEventDate: Date?
    private var lastCompactionDate: Date?
    private let maxEventsFileSizeBytes: UInt64 = 512 * 1024
    private let maxEventsFileLines = 1200
    private let minCompactionInterval: TimeInterval = 30
    private let maxRequestFileBytes = 1_048_576

    var eventsFileURL: URL {
        Self.eventsFileURL
    }

    init(settingsManager: SettingsManager) {
        self.settingsManager = settingsManager
    }

    // MARK: - Public API

    func publish(
        source: String,
        kind: AgentEventKind,
        title: String? = nil,
        message: String? = nil,
        ttl: TimeInterval? = nil
    ) {
        let normalizedSource = source.trimmingCharacters(in: .whitespacesAndNewlines)
        guard isAllowedSource(normalizedSource) else {
            debugLog("ignored unsupported source=\(normalizedSource)")
            return
        }
        let normalizedTitle = title?.trimmingCharacters(in: .whitespacesAndNewlines)

        let resolvedTitle: String
        if let normalizedTitle, !normalizedTitle.isEmpty {
            resolvedTitle = normalizedTitle
        } else {
            resolvedTitle = defaultTitle(for: kind, source: normalizedSource)
        }

        let event = AgentEvent(
            id: UUID(),
            source: normalizedSource,
            kind: kind,
            title: resolvedTitle,
            message: message?.trimmingCharacters(in: .whitespacesAndNewlines),
            ttl: resolvedTTL(for: kind, source: normalizedSource, payloadTTL: ttl),
            createdAt: Date()
        )

        showEvent(event)
    }

    /// Shows a short informational island for downloads, calendar or AirPods.
    /// Glances never interrupt a pending approval.
    func publishGlance(
        source: String,
        title: String,
        detail: String?,
        style: AgentGlanceStyle,
        actionURL: URL?,
        ttl: TimeInterval,
        batteryParts: [GlanceBatteryPart] = [],
        action: GlanceAction? = nil,
        progressKey: String? = nil,
        isSticky: Bool = false,
        buttons: [GlanceButton] = []
    ) {

        let event = AgentEvent(
            id: UUID(),
            source: source,
            kind: .completed,
            title: title,
            message: nil,
            ttl: min(max(ttl, 1.5), 15),
            createdAt: Date(),
            detail: detail,
            glance: style,
            actionURL: actionURL,
            action: action,
            batteryParts: batteryParts,
            progressKey: progressKey,
            isSticky: isSticky,
            buttons: buttons
        )

        guard pendingApprovals.isEmpty else {
            // Approvals own the island; a sticky glance waits its turn.
            if isSticky {
                parkedSticky = event
            }
            return
        }
        showEvent(event)
    }

    /// Removes the glance from `source`, on screen or parked, for example a finished download.
    /// The alert you closed yourself, so the island hides it at once instead of keeping
    /// a finished-task alert up for its full time.
    private(set) var explicitlyDismissedID: UUID?

    func dismissGlance(source: String) {
        if parkedSticky?.source == source {
            parkedSticky = nil
        }
        guard let currentEvent, currentEvent.glance != nil, currentEvent.source == source else { return }
        explicitlyDismissedID = currentEvent.id
        clearTask?.cancel()
        clearTask = nil
        restoreParkedOrClear()
    }

    /// The X button: closes whatever alert is showing, except an approval, which has its
    /// own Allow and Deny.
    func dismissCurrentEvent() {
        guard let currentEvent, currentEvent.approval == nil else { return }
        explicitlyDismissedID = currentEvent.id
        clearTask?.cancel()
        clearTask = nil
        if parkedSticky?.id == currentEvent.id {
            parkedSticky = nil
        }
        restoreParkedOrClear()
    }

    func handleGlanceButton(_ event: AgentEvent, _ button: GlanceButton) {
        switch button.action {
        case let .open(url):
            NSWorkspace.shared.open(url)
        case let .openSession(id, source):
            if !sessionTracker.open(sessionID: id, source: source),
               let app = NSRunningApplication.runningApplications(withBundleIdentifier: source == "codex" ? "com.openai.codex" : "com.anthropic.claudefordesktop").first {
                app.activate(options: [.activateAllWindows])
            }
        case .dismiss:
            break
        }
        dismissGlance(source: event.source)
    }

    /// Shows the parked sticky glance again, or empties the island.
    private func restoreParkedOrClear() {
        if let parked = parkedSticky, pendingApprovals.isEmpty {
            parkedSticky = nil
            currentEvent = parked
        } else {
            currentEvent = nil
        }
        eventID += 1
    }

    /// Before something else takes the island, keep a sticky glance so it can come back.
    private func parkCurrentIfSticky(beforeShowing next: AgentEvent) {
        guard let current = currentEvent, current.isSticky, current.id != next.id else { return }
        if next.isSticky && next.source == current.source {
            return
        }
        parkedSticky = current
    }

    func dismissCurrentGlance() {
        guard let currentEvent, currentEvent.glance != nil else { return }
        dismissGlance(source: currentEvent.source)
    }

    func decide(_ request: AgentApprovalRequest, _ decision: AgentApprovalDecision) {
        writeDecision(decision, for: request.id)
        if decision == .approve {
            sessionTracker.markWorking(sessionID: request.sessionID)
        }
        removePendingApprovals(where: { $0.id == request.id }, release: false)
    }

    func start() {
        guard fileEventSource == nil, fallbackWatchTask == nil else { return }

        do {
            try AgentHookPaths.ensureDirectories()
            try ensureEventsFile()
            compactEventsFileIfNeeded(force: true)
            readOffset = currentFileSize()
        } catch {
            return
        }

        sweepStaleProtocolFiles()
        bindApprovalSettings()
        startFileWatcher()
    }

    func stop() {
        stopFileWatcher()
        fallbackWatchTask?.cancel()
        fallbackWatchTask = nil
        clearTask?.cancel()
        clearTask = nil
        expiryTask?.cancel()
        expiryTask = nil
        cancellables.removeAll()
        // Let any waiting hooks fall back to the agent's own prompt.
        for request in pendingApprovals {
            writeDecision(.answerInTerminal, for: request.id)
        }
        pendingApprovals.removeAll()
    }

    // MARK: - Settings

    private func bindApprovalSettings() {
        settingsManager.$approveFromNotch
            .combineLatest(settingsManager.$approvalWaitSeconds)
            .sink { enabled, seconds in
                AgentHookPaths.writeApprovalWaitSeconds(enabled ? Int(seconds.rounded()) : 0)
            }
            .store(in: &cancellables)
    }

    // MARK: - File watching

    private func startFileWatcher() {
        guard fileEventSource == nil else { return }

        let descriptor = open(eventsFileURL.path, O_EVTONLY)
        guard descriptor >= 0 else {
            startFallbackWatcher()
            return
        }

        fallbackWatchTask?.cancel()
        fallbackWatchTask = nil

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: descriptor,
            eventMask: [.write, .extend, .delete, .rename, .revoke],
            queue: .main
        )
        source.setEventHandler { [weak self] in
            MainActor.assumeIsolated {
                self?.handleFileSystemEvent()
            }
        }
        source.setCancelHandler {
            close(descriptor)
        }

        fileEventSource = source
        source.resume()
    }

    private func stopFileWatcher() {
        fileEventSource?.cancel()
        fileEventSource = nil
    }

    private func handleFileSystemEvent() {
        guard let fileEventSource else { return }
        let event = fileEventSource.data

        readPendingEvents()

        let replacementEvents: DispatchSource.FileSystemEvent = [.delete, .rename, .revoke]
        guard !event.intersection(replacementEvents).isEmpty else { return }

        stopFileWatcher()
        try? ensureEventsFile()
        readOffset = currentFileSize()
        startFileWatcher()
    }

    private func startFallbackWatcher() {
        guard fallbackWatchTask == nil else { return }

        fallbackWatchTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(5))
                guard !Task.isCancelled, let self else { return }
                self.readPendingEvents()

                // The probe descriptor is only used to see whether event watching is available.
                let probe = open(self.eventsFileURL.path, O_EVTONLY)
                if probe >= 0 {
                    close(probe)
                    self.fallbackWatchTask = nil
                    self.startFileWatcher()
                    return
                }
            }
        }
    }

    private func readPendingEvents() {
        guard fileManager.fileExists(atPath: eventsFileURL.path) else {
            try? ensureEventsFile()
            readOffset = 0
            return
        }

        let nextFileSize = currentFileSize()
        guard nextFileSize >= readOffset else {
            readOffset = nextFileSize
            return
        }
        guard nextFileSize > readOffset else { return }

        guard let handle = try? FileHandle(forReadingFrom: eventsFileURL) else { return }
        defer {
            try? handle.close()
        }

        do {
            try handle.seek(toOffset: readOffset)
            let data = handle.readDataToEndOfFile()
            readOffset += UInt64(data.count)
            decodeEvents(from: data)
            compactEventsFileIfNeeded()
        } catch {
            readOffset = nextFileSize
        }
    }

    private func decodeEvents(from data: Data) {
        guard let rawText = String(data: data, encoding: .utf8) else { return }

        for line in rawText.split(whereSeparator: \.isNewline) {
            let text = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty, text.utf8.count < 64 * 1024, let lineData = text.data(using: .utf8) else { continue }
            guard let payload = try? JSONDecoder().decode(AgentEventPayload.self, from: lineData) else { continue }
            handle(payload)
        }
    }

    // MARK: - Event routing

    private func handle(_ payload: AgentEventPayload) {
        let source = payload.source?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard isAllowedSource(source) else {
            debugLog("ignored unsupported source=\(source)")
            return
        }

        let kind = payload.type ?? .completed
        let requestID = nonEmpty(payload.requestID)
        let sessionID = nonEmpty(payload.sessionID)
        let toolName = nonEmpty(payload.toolName)

        if let sessionID, source == "claude" || source == "codex" {
            // A notch request that timed out or was answered elsewhere is not new activity.
            let isRequestBookkeeping = kind == .clear && requestID != nil
            if !isRequestBookkeeping {
                sessionTracker.record(
                    source: source,
                    sessionID: sessionID,
                    hookEvent: nonEmpty(payload.hookEvent),
                    kind: kind,
                    toolName: toolName,
                    stepHint: nonEmpty(payload.step),
                    cwd: nonEmpty(payload.cwd),
                    pid: payload.pid
                )
            }
        }

        switch kind {
        case .accessRequest:
            if let requestID {
                enqueueApproval(id: requestID, source: source, sessionID: sessionID, toolName: toolName)
                return
            }
            // Notification-style alerts duplicate a request already on screen.
            if pendingApprovals.contains(where: { $0.source == source && (sessionID == nil || $0.sessionID == sessionID) }) {
                return
            }
            if isShowingQuestion(for: sessionID) { return }

        case .waiting:
            if isShowingQuestion(for: sessionID) { return }

        case .clear:
            if let sessionID { questionShownAt[sessionID] = nil }
            if let requestID {
                removePendingApprovals(where: { $0.id == requestID }, release: false)
                return
            }
            if let sessionID {
                // The tool ran or the user moved on, so the request was answered in the agent.
                removePendingApprovals(where: { request in
                    request.sessionID == sessionID &&
                        (toolName == nil || request.toolName == toolName)
                }, release: true)
            }
            if pendingApprovals.isEmpty {
                clearCurrentEvent(for: source)
            }
            return

        case .completed:
            if let payloadID = nonEmpty(payload.payloadID) {
                presentCompletion(source: source, payload: payload, payloadID: payloadID)
                return
            }

        default:
            break
        }

        guard let event = makeEvent(from: payload, source: source) else { return }
        showEvent(event)
    }

    private func makeEvent(from payload: AgentEventPayload, source: String, detail: String? = nil) -> AgentEvent? {
        let kind = payload.type ?? .completed
        let title = payload.title?.trimmingCharacters(in: .whitespacesAndNewlines)
        let message = payload.message?.trimmingCharacters(in: .whitespacesAndNewlines)
        var ttl = resolvedTTL(for: kind, source: source, payloadTTL: payload.ttl)
        if detail != nil {
            ttl = min(ttl + 2, 10)
        }
        let normalizedTitle = title?.isEmpty == false ? title : defaultTitle(for: kind, source: source)
        let sessionID = nonEmpty(payload.sessionID)

        // Agent alerts get a button that jumps to their session. The button layout needs a
        // detail line, so alerts without a summary name the project instead.
        var detail = detail
        var buttons: [GlanceButton] = []
        if let sessionID, source == "claude" || source == "codex",
           [.completed, .failed, .waiting, .accessRequest].contains(kind) {
            if detail == nil {
                let session = sessionTracker.sessions.first { $0.id == sessionID }
                detail = session?.project ?? (message?.isEmpty == false ? message : nil)
            }
            if detail != nil {
                buttons = [GlanceButton(
                    title: "Open session",
                    systemImage: "arrow.up.forward.app",
                    isPrimary: true,
                    action: .openSession(id: sessionID, source: source)
                )]
                // Long enough to reach the button.
                ttl = max(ttl, 8)
            }
        }

        return AgentEvent(
            id: UUID(),
            source: source,
            kind: kind,
            title: normalizedTitle ?? defaultTitle(for: kind, source: source),
            message: message?.isEmpty == false ? message : nil,
            ttl: ttl,
            createdAt: Date(),
            detail: detail,
            buttons: buttons,
            sessionID: sessionID
        )
    }

    // MARK: - Holding while the notch is open

    /// True while you are using the opened notch. New alerts wait instead of covering it.
    private var isHolding = false
    private var heldEvents: [AgentEvent] = []
    private var heldApproval = false

    func setHolding(_ holding: Bool) {
        guard holding != isHolding else { return }
        isHolding = holding
        guard !holding else { return }

        // An approval comes first; the agent is blocked on it.
        if heldApproval {
            heldApproval = false
            heldEvents.removeAll()
            presentHeadApproval(playSound: false)
            return
        }
        // Show them in order: a sticky one (a meeting reminder) parks behind later ones.
        let events = heldEvents
        heldEvents.removeAll()
        for event in events {
            showEvent(event, playSound: false)
        }
    }

    private func showEvent(_ event: AgentEvent, playSound: Bool = true) {
        if event.kind == .clear {
            // Activity from the agent makes its held "waiting" or "needs you" alert stale.
            heldEvents.removeAll {
                $0.source.lowercased() == event.source.lowercased() && $0.kind != .completed && !$0.isSticky
            }
            clearCurrentEvent(for: event.source)
            return
        }

        if isHolding {
            heldEvents.removeAll { duplicateKey(for: $0) == duplicateKey(for: event) }
            heldEvents.append(event)
            heldEvents = Array(heldEvents.suffix(5))
            // The sound still tells you something arrived.
            playAgentAlertSoundIfNeeded(for: event)
            debugLog("event held while the notch is open source=\(event.source)")
            return
        }

        // A pending approval owns the island until it is answered.
        if !pendingApprovals.isEmpty, event.approval == nil {
            debugLog("event suppressed while approval pending source=\(event.source)")
            return
        }

        let eventKey = duplicateKey(for: event)
        let now = Date()

        if event.approval == nil {
            if let currentEvent,
               duplicateKey(for: currentEvent) == eventKey {
                debugLog("duplicate active event ignored key=\(eventKey)")
                return
            }

            if let lastShownEventKey,
               lastShownEventKey == eventKey,
               let lastShownEventDate,
               now.timeIntervalSince(lastShownEventDate) < max(event.ttl + 1, 3) {
                debugLog("recent duplicate event ignored key=\(eventKey)")
                return
            }
        }

        lastShownEventKey = eventKey
        lastShownEventDate = now
        parkCurrentIfSticky(beforeShowing: event)
        if event.isSticky, parkedSticky?.source == event.source {
            parkedSticky = nil
        }
        currentEvent = event
        eventID += 1
        debugLog("show event source=\(event.source) kind=\(event.kind.rawValue) ttl=\(event.ttl)")
        if playSound {
            playAgentAlertSoundIfNeeded(for: event)
        }

        clearTask?.cancel()
        guard shouldAutoClear(event) else {
            clearTask = nil
            return
        }

        clearTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(event.ttl))
            guard !Task.isCancelled else { return }
            await MainActor.run {
                guard self?.currentEvent?.id == event.id else { return }
                self?.restoreParkedOrClear()
            }
        }
    }

    private func clearCurrentEvent(for source: String) {
        let normalizedSource = source.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard let currentEvent,
              currentEvent.approval == nil,
              currentEvent.source.lowercased() == normalizedSource else {
            return
        }

        // Keep summaries and glances on screen for their full duration.
        guard currentEvent.kind != .completed, !currentEvent.isSticky else { return }

        clearTask?.cancel()
        clearTask = nil
        restoreParkedOrClear()
    }

    // MARK: - Approvals

    private func enqueueApproval(id: String, source: String, sessionID: String?, toolName: String?) {
        guard Self.isSafeIdentifier(id), !pendingApprovals.contains(where: { $0.id == id }) else { return }

        let requestURL = AgentHookPaths.requestURL(for: id)
        guard let attributes = try? fileManager.attributesOfItem(atPath: requestURL.path),
              let size = (attributes[.size] as? NSNumber)?.intValue,
              size <= maxRequestFileBytes,
              let data = try? Data(contentsOf: requestURL),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            // Without the request we cannot summarize it, so let the agent prompt instead.
            writeDecision(.answerInTerminal, for: id)
            return
        }

        let tool = (object["tool_name"] as? String) ?? toolName ?? "Tool"
        let input = object["tool_input"] as? [String: Any] ?? [:]
        let cwd = object["cwd"] as? String

        // A question is not a permission: let the agent show it, and point to the session.
        if tool == "AskUserQuestion" {
            writeDecision(.answerInTerminal, for: id)
            presentQuestion(
                source: source,
                sessionID: sessionID ?? (object["session_id"] as? String),
                input: input,
                project: cwd.map { URL(fileURLWithPath: $0).lastPathComponent }
            )
            return
        }
        let description = AgentToolSummarizer.describe(toolName: tool, input: input)
        let wait = max(5, settingsManager.approvalWaitSeconds)
        let now = Date()

        let request = AgentApprovalRequest(
            id: id,
            source: source,
            sessionID: sessionID ?? (object["session_id"] as? String),
            toolName: tool,
            toolLabel: description.label,
            summary: description.summary,
            detail: description.detail,
            project: cwd.map { URL(fileURLWithPath: $0).lastPathComponent },
            receivedAt: now,
            deadline: now.addingTimeInterval(wait + 3)
        )

        let wasEmpty = pendingApprovals.isEmpty
        pendingApprovals.append(request)
        scheduleExpiryCheck()

        if wasEmpty {
            presentHeadApproval(playSound: true)
        } else if settingsManager.enableCodexApprovalAlertSound {
            CodexAlertSoundPlayer.shared.play(for: .accessRequest)
        }
    }

    /// Sessions whose question is on screen, so the agent's own "needs input" alert
    /// for the same question does not replace it.
    private var questionShownAt: [String: Date] = [:]

    private func presentQuestion(source: String, sessionID: String?, input: [String: Any], project: String?) {
        let questions = input["questions"] as? [[String: Any]] ?? []
        let first = (questions.first?["question"] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        var text = first?.isEmpty == false ? first! : "Has a question for you"
        if questions.count > 1 {
            text += " (+\(questions.count - 1) more)"
        }

        let name = source.lowercased() == "codex" ? "Codex" : "Claude"
        var title = "\(name) asked a question"
        if let project, !project.isEmpty {
            title += " · \(project)"
        }

        var buttons: [GlanceButton] = []
        if let sessionID {
            buttons = [GlanceButton(
                title: "Open session",
                systemImage: "arrow.up.forward.app",
                isPrimary: true,
                action: .openSession(id: sessionID, source: source)
            )]
            questionShownAt[sessionID] = Date()
        }

        showEvent(AgentEvent(
            id: UUID(),
            source: source,
            kind: .waiting,
            title: title,
            message: nil,
            ttl: 30,
            createdAt: Date(),
            detail: text,
            buttons: buttons,
            sessionID: sessionID
        ))
    }

    private func isShowingQuestion(for sessionID: String?) -> Bool {
        guard let sessionID, let shown = questionShownAt[sessionID] else { return false }
        return Date().timeIntervalSince(shown) < 60
    }

    private func removePendingApprovals(where predicate: (AgentApprovalRequest) -> Bool, release: Bool) {
        let removed = pendingApprovals.filter(predicate)
        guard !removed.isEmpty else { return }

        let headID = pendingApprovals.first?.id
        pendingApprovals.removeAll(where: predicate)

        if release {
            for request in removed {
                writeDecision(.answerInTerminal, for: request.id)
            }
        }

        if pendingApprovals.isEmpty {
            expiryTask?.cancel()
            expiryTask = nil
            if currentEvent?.approval != nil {
                clearTask?.cancel()
                restoreParkedOrClear()
            }
        } else if pendingApprovals.first?.id != headID {
            presentHeadApproval(playSound: false)
        }
    }

    private func presentHeadApproval(playSound: Bool) {
        guard let head = pendingApprovals.first else { return }

        if isHolding {
            heldApproval = true
            if playSound {
                playAgentAlertSoundIfNeeded(for: AgentEvent(id: UUID(), source: head.source, kind: .accessRequest, title: "", message: nil, ttl: 0, createdAt: Date()))
            }
            return
        }

        let event = AgentEvent(
            id: UUID(),
            source: head.source,
            kind: .accessRequest,
            title: "Needs approval",
            message: nil,
            ttl: head.deadline.timeIntervalSinceNow,
            createdAt: Date(),
            approval: head
        )

        clearTask?.cancel()
        clearTask = nil
        parkCurrentIfSticky(beforeShowing: event)
        currentEvent = event
        eventID += 1
        if playSound {
            playAgentAlertSoundIfNeeded(for: event)
        }
    }

    private func scheduleExpiryCheck() {
        guard expiryTask == nil else { return }

        expiryTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard let self, !Task.isCancelled else { return }
                let now = Date()
                self.removePendingApprovals(where: { $0.deadline <= now }, release: false)
                if self.pendingApprovals.isEmpty {
                    self.expiryTask = nil
                    return
                }
            }
        }
    }

    private func writeDecision(_ decision: AgentApprovalDecision, for id: String) {
        guard Self.isSafeIdentifier(id) else { return }

        let body: [String: Any]
        switch decision {
        case .approve:
            body = ["hookSpecificOutput": [
                "hookEventName": "PermissionRequest",
                "decision": ["behavior": "allow"]
            ]]
        case .deny:
            body = ["hookSpecificOutput": [
                "hookEventName": "PermissionRequest",
                "decision": ["behavior": "deny", "message": "Denied from BetterNotch."]
            ]]
        case .answerInTerminal:
            body = ["release": true]
        }

        guard let data = try? JSONSerialization.data(withJSONObject: body, options: [.sortedKeys]) else { return }
        try? AgentHookPaths.ensureDirectories()
        try? data.write(to: AgentHookPaths.decisionURL(for: id), options: .atomic)
    }

    // MARK: - Completion summaries

    private func presentCompletion(source: String, payload: AgentEventPayload, payloadID: String) {
        guard Self.isSafeIdentifier(payloadID) else { return }
        let fileURL = AgentHookPaths.requestURL(for: payloadID)
        let wantsSummary = settingsManager.showCompletionSummary
        let maxBytes = maxRequestFileBytes

        Task.detached(priority: .utility) {
            var found: String?
            if wantsSummary,
               let size = (try? FileManager.default.attributesOfItem(atPath: fileURL.path)[.size] as? NSNumber)?.intValue,
               size <= maxBytes,
               let data = try? Data(contentsOf: fileURL),
               let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                found = AgentTranscriptSummarizer.summary(fromHookPayload: object)
            }
            try? FileManager.default.removeItem(at: fileURL)
            let summary = found

            await MainActor.run { [weak self] in
                guard let self, let event = self.makeEvent(from: payload, source: source, detail: summary) else { return }
                self.showEvent(event)
            }
        }
    }

    // MARK: - Helpers

    private func shouldAutoClear(_ event: AgentEvent) -> Bool {
        if event.approval != nil || event.isSticky {
            return false
        }

        let source = event.source.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if Self.stickyApprovalSources.contains(source), event.kind == .accessRequest {
            return false
        }

        return true
    }

    private func playAgentAlertSoundIfNeeded(for event: AgentEvent) {
        let source = event.source.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard Self.soundEnabledSources.contains(source) else { return }
        guard event.kind != .clear else { return }

        switch event.kind {
        case .accessRequest, .waiting:
            guard settingsManager.enableCodexApprovalAlertSound else { return }
        case .completed:
            guard settingsManager.enableCodexCompletedAlertSound else { return }
        case .failed, .cancelled, .started, .progress:
            guard settingsManager.enableCodexCompletedAlertSound else { return }
        case .clear:
            return
        }

        CodexAlertSoundPlayer.shared.play(for: event.kind)
    }

    private func duplicateKey(for event: AgentEvent) -> String {
        [
            event.source.lowercased(),
            event.kind.rawValue,
            event.title,
            event.message ?? "",
            event.detail ?? "",
            event.approval?.id ?? "",
            event.progressKey ?? ""
        ].joined(separator: "|")
    }

    private func resolvedTTL(
        for kind: AgentEventKind,
        source: String,
        payloadTTL: TimeInterval?
    ) -> TimeInterval {
        let normalizedSource = source.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        if Self.soundEnabledSources.contains(normalizedSource), kind == .completed {
            return min(max(settingsManager.codexCompletedAlertDuration, 1.5), 8)
        }

        return min(max(payloadTTL ?? defaultTTL(for: kind), 1.5), 30)
    }

    private func defaultTTL(for kind: AgentEventKind) -> TimeInterval {
        switch kind {
        case .clear:
            return 1.5
        case .accessRequest, .waiting:
            return 2
        case .failed, .cancelled:
            return 2
        case .started, .progress:
            return 2
        case .completed:
            return 3.0
        }
    }

    private func defaultTitle(for kind: AgentEventKind, source: String = "") -> String {
        let normalizedSource = source.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        switch kind {
        case .clear:
            return ""
        case .accessRequest:
            if Self.stickyApprovalSources.contains(normalizedSource) {
                return "Need approval"
            }
            return "Access requested"
        case .waiting:
            return "Waiting for input"
        case .completed:
            return "Task completed"
        case .failed:
            return "Task failed"
        case .started:
            return "Task started"
        case .progress:
            return "Working"
        case .cancelled:
            return "Task cancelled"
        }
    }

    private func nonEmpty(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else { return nil }
        return trimmed
    }

    private func isAllowedSource(_ source: String) -> Bool {
        let normalizedSource = source.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return Self.allowedSources.contains(normalizedSource)
    }

    nonisolated static func isSafeIdentifier(_ value: String) -> Bool {
        !value.isEmpty && value.count <= 64 &&
            value.unicodeScalars.allSatisfy { CharacterSet.alphanumerics.contains($0) || $0 == "-" }
    }

    private static let allowedSources: Set<String> = [
        "codex",
        "claude",
        "cursor"
    ]

    private static let stickyApprovalSources: Set<String> = [
        "codex",
        "claude",
        "cursor"
    ]

    private static let soundEnabledSources: Set<String> = [
        "codex",
        "claude"
    ]

    private func sweepStaleProtocolFiles() {
        let cutoff = Date().addingTimeInterval(-15 * 60)
        for directory in [AgentHookPaths.requestsDirectoryURL, AgentHookPaths.decisionsDirectoryURL] {
            guard let urls = try? fileManager.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: [.contentModificationDateKey]
            ) else { continue }

            for url in urls {
                let modified = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
                if let modified, modified < cutoff {
                    try? fileManager.removeItem(at: url)
                }
            }
        }
    }

    private func ensureEventsFile() throws {
        try fileManager.createDirectory(
            at: Self.eventsDirectoryURL,
            withIntermediateDirectories: true
        )

        guard !fileManager.fileExists(atPath: eventsFileURL.path) else { return }
        fileManager.createFile(atPath: eventsFileURL.path, contents: nil)
    }

    private func compactEventsFileIfNeeded(force: Bool = false) {
        let now = Date()
        if !force,
           let lastCompactionDate,
           now.timeIntervalSince(lastCompactionDate) < minCompactionInterval {
            return
        }

        let fileSize = currentFileSize()
        guard force || fileSize > maxEventsFileSizeBytes else { return }

        guard let data = try? Data(contentsOf: eventsFileURL),
              let text = String(data: data, encoding: .utf8) else {
            return
        }

        let lines = text
            .split(whereSeparator: \.isNewline)
            .map(String.init)
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

        guard lines.count > maxEventsFileLines else {
            lastCompactionDate = now
            return
        }

        let keptLines = lines.suffix(maxEventsFileLines)
        let compacted = keptLines.joined(separator: "\n") + "\n"

        do {
            try compacted.write(to: eventsFileURL, atomically: true, encoding: .utf8)
            readOffset = currentFileSize()
            lastCompactionDate = now
        } catch {
            return
        }
    }

    private func currentFileSize() -> UInt64 {
        guard let attributes = try? fileManager.attributesOfItem(atPath: eventsFileURL.path),
              let size = attributes[.size] as? NSNumber else {
            return 0
        }

        return size.uint64Value
    }

    private static var eventsDirectoryURL: URL {
        AgentHookPaths.baseDirectoryURL
    }

    private static var eventsFileURL: URL {
        eventsDirectoryURL.appendingPathComponent("agent-events.jsonl")
    }

    private func debugLog(_ message: @autoclosure () -> String) {
        #if AGENT_EVENT_DEBUG
        print("[AgentEvent] \(message())")
        #endif
    }
}

@MainActor
final class CodexAlertSoundPlayer {
    static let shared = CodexAlertSoundPlayer()

    private let approvalSound = NSSound(named: NSSound.Name("Ping"))
    private let completedSound = NSSound(named: NSSound.Name("Glass"))
    private let fallbackSound = NSSound(named: NSSound.Name("Submarine"))
    private var lastPlayDate: Date?

    private init() {}

    func play(for kind: AgentEventKind, bypassThrottle: Bool = false) {
        let now = Date()
        if !bypassThrottle, let lastPlayDate, now.timeIntervalSince(lastPlayDate) < 0.35 {
            return
        }

        guard let sound = sound(for: kind) else { return }

        lastPlayDate = now
        sound.stop()
        sound.volume = kind == .accessRequest ? 0.24 : 0.18
        sound.play()
    }

    private func sound(for kind: AgentEventKind) -> NSSound? {
        switch kind {
        case .accessRequest, .waiting:
            return approvalSound ?? fallbackSound
        case .completed:
            return completedSound ?? fallbackSound
        case .failed, .cancelled:
            return fallbackSound ?? approvalSound ?? completedSound
        case .clear, .started, .progress:
            return completedSound ?? fallbackSound
        }
    }
}


/// Live values for progress glances, observed directly by the island view so a
/// sticky glance can update without being re-presented.
@MainActor
final class GlanceProgressStore: ObservableObject {
    static let shared = GlanceProgressStore()

    struct Entry: Equatable {
        /// 0...1, or nil when the total size is unknown.
        var fraction: Double?
        var bytes: Int64
        var totalBytes: Int64?
        var bytesPerSecond: Double
    }

    @Published private(set) var entries: [String: Entry] = [:]

    func update(_ key: String, _ entry: Entry) {
        if entries[key] != entry {
            entries[key] = entry
        }
    }

    func remove(_ key: String) {
        entries.removeValue(forKey: key)
    }
}
