//
//  ExtrasPanelView.swift
//  Notchly
//
//  The tabbed panel under the battery panel or music player when the notch is opened:
//  agent sessions, AI usage, listening ports, system stats, a file shelf, a quick note,
//  and the sound output picker. Swipe sideways on the trackpad to change tabs.
//

import AppKit
import Combine
import SwiftUI

// MARK: - Model

@MainActor
final class ExtrasPanelModel: ObservableObject {
    enum Tab: String, CaseIterable, Identifiable {
        case agents, usage, ask, ports, system, shelf, note, output
        var id: String { rawValue }

        var title: String {
            switch self {
            case .agents: return "Agents"
            case .usage: return "Usage"
            case .ports: return "Ports"
            case .system: return "System"
            case .shelf: return "Shelf"
            case .note: return "Note"
            case .ask: return "Ask"
            case .output: return "Output"
            }
        }

        var symbol: String {
            switch self {
            case .agents: return "sparkles"
            case .usage: return "gauge.with.dots.needle.50percent"
            case .ports: return "network"
            case .system: return "cpu"
            case .shelf: return "tray.full"
            case .note: return "note.text"
            case .ask: return "bubble.left.and.text.bubble.right"
            case .output: return "speaker.wave.2"
            }
        }
    }

    /// The tab the user picked last; nil until they pick one.
    @Published private(set) var chosenTab: Tab?
    @Published var noteText: String {
        didSet { UserDefaults.standard.set(noteText, forKey: "quickNoteText") }
    }
    @Published var noteDraft = ""
    @Published private(set) var isEditingNote = false
    /// The Ask tab's conversation; its changes resize the panel.
    let askAI = AskAIModel()

    private var resignObserver: NSObjectProtocol?
    private var askAIChanges: AnyCancellable?

    init() {
        chosenTab = UserDefaults.standard.string(forKey: "extrasPanelTab").flatMap(Tab.init(rawValue:))
        noteText = UserDefaults.standard.string(forKey: "quickNoteText") ?? ""
        askAIChanges = askAI.objectWillChange.sink { [weak self] _ in self?.objectWillChange.send() }
    }

    /// True while you are typing in the notch, so it stays open.
    var isTyping: Bool { isEditingNote || askAI.isEditing }

    private var swipeTravel: CGFloat = 0
    private var swipeConsumed = false

    /// Two-finger sideways swipe anywhere on the opened notch moves exactly one tab per
    /// gesture. Momentum after the
    /// fingers lift is ignored, which is what made hard swipes jump two tabs.
    func handleSwipe(_ event: NSEvent, tabs: [Tab], selected: Tab?) {
        guard event.momentumPhase.isEmpty else { return }

        if event.phase.contains(.began) || event.phase.contains(.mayBegin) {
            swipeTravel = 0
            swipeConsumed = false
        }
        if event.phase.contains(.ended) || event.phase.contains(.cancelled) {
            swipeTravel = 0
            swipeConsumed = false
            return
        }
        // Mouse wheels have no phases; treat each sideways tick as its own gesture.
        let isWheel = event.phase.isEmpty
        guard !swipeConsumed || isWheel else { return }

        let deltaX = event.scrollingDeltaX
        let deltaY = event.scrollingDeltaY
        guard abs(deltaX) > abs(deltaY) else { return }

        swipeTravel += deltaX
        guard abs(swipeTravel) >= (isWheel ? 1 : 24),
              let selected, let index = tabs.firstIndex(of: selected) else { return }

        // Fingers moving left bring in the tab on the right, like swiping between pages.
        let next = swipeTravel < 0 ? index + 1 : index - 1
        swipeTravel = 0
        swipeConsumed = true
        guard tabs.indices.contains(next) else { return }
        withAnimation(.smooth(duration: 0.22, extraBounce: 0)) {
            choose(tabs[next])
        }
    }

    func choose(_ tab: Tab) {
        chosenTab = tab
        UserDefaults.standard.set(tab.rawValue, forKey: "extrasPanelTab")
    }

    func availableTabs(_ settings: SettingsManager) -> [Tab] {
        var tabs: [Tab] = []
        if settings.showAgentSessions { tabs.append(.agents) }
        if settings.showUsageTab { tabs.append(.usage) }
        if settings.showAskAI { tabs.append(.ask) }
        if settings.showPortsPanel { tabs.append(.ports) }
        if settings.showSystemTab { tabs.append(.system) }
        if settings.showFileShelf { tabs.append(.shelf) }
        if settings.showQuickNote { tabs.append(.note) }
        if settings.showOutputPicker { tabs.append(.output) }
        return tabs
    }

    /// The tab to show: the user's pick, else Agents while sessions are active, else Ports.
    func resolvedTab(available: [Tab], activeSessions: Int) -> Tab? {
        if let chosenTab, available.contains(chosenTab) { return chosenTab }
        if activeSessions > 0, available.contains(.agents) { return .agents }
        if available.contains(.ports) { return .ports }
        return available.first
    }

    // MARK: Note editing

    func beginEditingNote() {
        guard !isEditingNote else { return }
        noteDraft = noteText
        isEditingNote = true
        IslandKeyFocus.begin()

        resignObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didResignKeyNotification,
            object: IslandKeyFocus.islandWindow,
            queue: .main
        ) { [weak self] _ in
            // Clicking into another app ends editing and keeps what was typed.
            MainActor.assumeIsolated { self?.commitNote() }
        }
    }

    func commitNote() {
        guard isEditingNote else { return }
        noteText = String(noteDraft.trimmingCharacters(in: .whitespacesAndNewlines).prefix(500))
        finishEditing()
    }

    func cancelNote() {
        guard isEditingNote else { return }
        finishEditing()
    }

    func clearNote() {
        noteText = ""
        noteDraft = ""
    }

    private func finishEditing() {
        isEditingNote = false
        if let resignObserver {
            NotificationCenter.default.removeObserver(resignObserver)
        }
        resignObserver = nil
        IslandKeyFocus.end()
    }
}

// MARK: - Keyboard focus

/// The island window is a non-activating panel that normally never takes the keyboard,
/// so clicks on its buttons never steal typing from your app. It accepts key focus only
/// while the quick note is being edited, then hands focus back.
@MainActor
enum IslandKeyFocus {
    private(set) static var allowsKey = false

    static var islandWindow: NSWindow? {
        NSApp.windows.first { $0 is IslandPanel }
    }

    static func begin() {
        allowsKey = true
        NSApp.activate()
        islandWindow?.makeKeyAndOrderFront(nil)
    }

    static func end() {
        guard allowsKey else { return }
        allowsKey = false
        // Deactivating returns the keyboard to the app you were using before.
        NSApp.deactivate()
    }
}

final class IslandPanel: NSPanel {
    override var canBecomeKey: Bool {
        MainActor.assumeIsolated { IslandKeyFocus.allowsKey }
    }

    override var canBecomeMain: Bool { false }
}

// MARK: - Panel

struct ExtrasPanelView: View {
    @ObservedObject var model: ExtrasPanelModel
    @ObservedObject var settingsManager: SettingsManager
    @ObservedObject var sessionTracker: AgentSessionTracker
    @ObservedObject var portsMonitor: ListeningPortsMonitor
    @ObservedObject var audioOutputs: AudioOutputManager
    @ObservedObject var usageMonitor: AIUsageMonitor
    @ObservedObject var systemMonitor: SystemStatsMonitor
    @ObservedObject var shelf: FileShelfModel
    @ObservedObject var micMute: MicMuteManager
    let width: CGFloat
    var isShelfDropTargeted = false
    /// A meeting counting down, shown as a strip above the tabs with an X to close it.
    var meeting: LiveActivity? = nil
    var onDismissMeeting: () -> Void = {}

    static let meetingStripHeight: CGFloat = 30

    /// Sideways trackpad travel so far in the current swipe.
    /// Set once a swipe has changed tab; cleared when the fingers lift.

    static let headerHeight: CGFloat = 26
    /// The panel starts this far below the top section (battery or music) above it.
    /// The island's height counts it, or the panel's bottom margin would be cut short.
    static let gapBelowTopSection: CGFloat = 8
    /// Extra room between the tab row and a tab's content. Only the System rings use it.
    static func contentGap(for tab: ExtrasPanelModel.Tab?) -> CGFloat {
        tab == .system ? 10 : 0
    }
    /// Room under the last row, so a hovered row's corners run parallel to the notch's.
    static let bottomPadding: CGFloat = IslandMetrics.rowEdgeInset
    static let agentRowHeight: CGFloat = IslandMetrics.rowHeight
    static let outputRowHeight: CGFloat = IslandMetrics.rowHeight
    static let noteHeight: CGFloat = 54
    /// The Ask tab: just the question field until there is a conversation to show above it.
    static let askConversationHeight: CGFloat = 196
    static func askHeight(hasConversation: Bool) -> CGFloat {
        hasConversation ? askConversationHeight + 8 + 30 + 4 : noteHeight
    }

    /// The battery panel and music player when the notch opens: fade in while sliding
    /// straight down from the top. No scaling, so nothing drifts sideways as the island
    /// widens. Leaves with a quick fade.
    static var openedContentTransition: AnyTransition {
        .asymmetric(
            insertion: .opacity
                .combined(with: .offset(y: -14))
                .animation(.smooth(duration: 0.36, extraBounce: 0).delay(0.04)),
            removal: .opacity.animation(.easeOut(duration: 0.12))
        )
    }

    /// The tab panel: the same slide down, just after the content above it.
    static var transition: AnyTransition {
        .asymmetric(
            insertion: .opacity
                .combined(with: .offset(y: -14))
                .animation(.smooth(duration: 0.36, extraBounce: 0).delay(0.1)),
            removal: .opacity.animation(.easeOut(duration: 0.12))
        )
    }

    static func height(
        tab: ExtrasPanelModel.Tab?,
        sessions: Int,
        ports: Int,
        outputs: Int,
        usageRows: Int = 1,
        shelfItems: Int = 0,
        askHasConversation: Bool = false,
        hasMeeting: Bool = false
    ) -> CGFloat {
        guard let tab else { return 0 }
        let content: CGFloat
        switch tab {
        case .agents: content = CGFloat(max(1, min(sessions, 6))) * agentRowHeight
        case .usage: content = UsageTabView.contentHeight(rows: usageRows)
        case .system: content = SystemTabView.contentHeight
        case .shelf: content = ShelfTabView.contentHeight(for: shelfItems)
        case .ports: content = PortsListView.contentHeight(for: ports)
        case .note: content = noteHeight
        case .ask: content = askHeight(hasConversation: askHasConversation)
        case .output: content = CGFloat(max(1, min(outputs, 6))) * outputRowHeight
        }
        return headerHeight + contentGap(for: tab) + content + bottomPadding + (hasMeeting ? meetingStripHeight : 0)
    }

    var body: some View {
        let tabs = model.availableTabs(settingsManager)
        let selected = model.resolvedTab(available: tabs, activeSessions: sessionTracker.activeCount)

        VStack(alignment: .leading, spacing: 4) {
            if let meeting {
                MeetingStrip(meeting: meeting, onDismiss: onDismissMeeting)
                    .frame(height: Self.meetingStripHeight - 4)
                    .transition(.opacity)
            }

            HStack(spacing: 4) {
                Spacer(minLength: 0)
                ForEach(tabs) { tab in
                    TabChip(
                        tab: tab,
                        count: count(for: tab),
                        isSelected: tab == selected,
                        hasAttention: tab == .agents && sessionTracker.sessions.contains { $0.state == .needsApproval }
                    ) {
                        withAnimation(.smooth(duration: 0.28, extraBounce: 0)) {
                            model.choose(tab)
                        }
                    }
                }
                Spacer(minLength: 0)
            }
            .frame(height: Self.headerHeight - 4)
            .padding(.bottom, Self.contentGap(for: selected))

            Group {
                switch selected {
                case .agents:
                    AgentSessionsListView(tracker: sessionTracker)
                case .usage:
                    UsageTabView(monitor: usageMonitor)
                case .system:
                    SystemTabView(monitor: systemMonitor)
                case .shelf:
                    ShelfTabView(shelf: shelf, isDropTargeted: isShelfDropTargeted)
                case .ports:
                    PortsListView(monitor: portsMonitor)
                case .note:
                    QuickNoteView(model: model)
                case .ask:
                    AskAIView(model: model.askAI)
                case .output:
                    AudioOutputListView(manager: audioOutputs)
                case nil:
                    EmptyView()
                }
            }
            .transition(.opacity)
            .id(selected)
        }
        .padding(.horizontal, IslandMetrics.contentInset)
        .frame(width: width, alignment: .topLeading)

    }

    private func count(for tab: ExtrasPanelModel.Tab) -> Int? {
        switch tab {
        case .agents: return sessionTracker.sessions.isEmpty ? nil : sessionTracker.sessions.count
        case .ports: return portsMonitor.panelPorts.isEmpty ? nil : portsMonitor.panelPorts.count
        case .shelf: return shelf.items.isEmpty ? nil : shelf.items.count
        case .usage, .system, .note, .ask, .output: return nil
        }
    }
}

/// Selected tab: icon and name. Others: icon only, so all tabs fit on one row.
private struct TabChip: View {
    let tab: ExtrasPanelModel.Tab
    let count: Int?
    let isSelected: Bool
    let hasAttention: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: tab.symbol)
                    .font(.system(size: 10.5, weight: .semibold))
                if isSelected {
                    Text(tab.title)
                        .font(.system(size: 11, weight: .semibold))
                        .fixedSize()
                }
                if let count, isSelected {
                    Text(verbatim: "\(count)")
                        .font(.system(size: 10.5, weight: .semibold).monospacedDigit())
                        .foregroundStyle(.white.opacity(0.6))
                }
            }
            .foregroundStyle(.white.opacity(isSelected ? 0.95 : 0.5))
            .padding(.horizontal, isSelected ? 9 : 7)
            .frame(height: 20)
            .background(Color.white.opacity(isSelected ? 0.14 : 0))
            .clipShape(Capsule())
            .overlay(alignment: .topTrailing) {
                if hasAttention {
                    Circle()
                        .fill(Color.orange)
                        .frame(width: 5, height: 5)
                        .offset(x: -1, y: 1)
                }
            }
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .help(Text(tab.title))
    }
}

/// The meeting countdown in the opened notch, with an X to stop counting down.
private struct MeetingStrip: View {
    let meeting: LiveActivity
    let onDismiss: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "calendar")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Color(red: 1.0, green: 0.42, blue: 0.4))
            Text(verbatim: meeting.title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white.opacity(0.9))
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: 6)
            Text("in")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.white.opacity(0.45))
            Text(timerInterval: Date()...max(Date(), meeting.date), countsDown: true, showsHours: false)
                .font(.system(size: 12, weight: .semibold).monospacedDigit())
                .foregroundStyle(Color(red: 1.0, green: 0.42, blue: 0.4))
                .fixedSize()
            NoticeCloseButton(action: onDismiss)
                .help(Text("Stop the countdown for this meeting"))
        }
        .padding(.leading, 10)
        .padding(.trailing, 4)
        .background(Capsule().fill(Color.white.opacity(0.07)))
    }
}

/// Mutes the microphone in every app. Red while muted.
struct MicMuteButton: View {
    @ObservedObject var micMute: MicMuteManager

    static let size: CGFloat = 30

    var body: some View {
        Button {
            micMute.toggle()
        } label: {
            Image(systemName: micMute.isMuted ? "mic.slash.fill" : "mic.fill")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(micMute.isMuted ? .white : .white.opacity(0.75))
                .frame(width: Self.size, height: Self.size)
                .background(Circle().fill(micMute.isMuted ? Color(red: 0.97, green: 0.32, blue: 0.29) : Color.white.opacity(0.1)))
                .contentShape(Circle())
                .contentTransition(.symbolEffect(.replace))
        }
        .buttonStyle(IslandControlButtonStyle(pressedScale: 0.9, hoverScale: 1.06, hoverBackgroundOpacity: 0.06))
        .help(Text(verbatim: helpText))
    }

    private var helpText: String {
        var text = micMute.isMuted ? "Microphones muted. Click to unmute." : "Mute every microphone"
        if !micMute.unmutableInputs.isEmpty {
            text += "\n" + micMute.unmutableInputs.joined(separator: ", ") + " cannot be muted from here."
        }
        return text
    }
}

// MARK: - Agents tab

private struct AgentSessionsListView: View {
    @ObservedObject var tracker: AgentSessionTracker
    @State private var hoveredIndex: Int?

    var body: some View {
        if tracker.sessions.isEmpty {
            Text("No agent sessions in the last 2 hours")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.white.opacity(0.45))
                .frame(height: ExtrasPanelView.agentRowHeight)
        } else {
            TimelineView(.periodic(from: .now, by: 30)) { context in
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(tracker.sessions.prefix(6).enumerated()), id: \.element.id) { index, session in
                        Button {
                            tracker.activate(session)
                        } label: {
                            AgentSessionRow(session: session, now: context.date)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .islandRow(height: ExtrasPanelView.agentRowHeight, isHighlighted: hoveredIndex == index)
                        .help(Text(verbatim: "\(session.sourceLabel) · \(session.displayName) · click to show it"))
                    }
                }
                .islandRowHover(rowHeight: ExtrasPanelView.agentRowHeight, hoveredIndex: $hoveredIndex)
            }
        }
    }
}

/// Sizes for an Agents row; the tab width is worked out from them.
enum AgentRowMetrics {
    static let maxNameWidth: CGFloat = 280
    static let maxStatusWidth: CGFloat = 210
    /// Everything in a row except the two texts: icon 16, four 8 pt gaps, the 6 pt
    /// minimum spacer, status dots 18 plus 5, time 30, and a few points of slack.
    static let fixedWidth: CGFloat = 16 + 4 * 8 + 6 + 18 + 5 + 30 + 4
    static let nameFont = NSFont.systemFont(ofSize: 12, weight: .medium)
    static let statusFont = NSFont.systemFont(ofSize: 11, weight: .medium)

    /// Width of the widest row's content, each text up to its cap.
    static func contentWidth(for sessions: [AgentSession]) -> CGFloat {
        sessions.map { session in
            let name = (session.displayName as NSString).size(withAttributes: [.font: nameFont]).width
            return min(ceil(name) + 2, maxNameWidth) + statusWidth(for: session) + fixedWidth
        }.max() ?? 0
    }

    /// The status text's own width, up to its cap, so it never claims space it does not use.
    static func statusWidth(for session: AgentSession) -> CGFloat {
        let width = (session.statusText as NSString).size(withAttributes: [.font: statusFont]).width
        return min(ceil(width) + 2, maxStatusWidth)
    }
}

private struct AgentSessionRow: View {
    let session: AgentSession
    let now: Date

    var body: some View {
        HStack(spacing: 8) {
            Group {
                if session.source == "codex" {
                    Image("CodexAgentIcon")
                        .resizable()
                        .renderingMode(.original)
                        .scaledToFit()
                } else {
                    Image(systemName: "sparkles")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Color(red: 0.85, green: 0.48, blue: 0.32))
                }
            }
            .frame(width: 16, height: 16)

            Text(verbatim: session.displayName)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.white.opacity(0.9))
                .lineLimit(1)
                .truncationMode(.tail)
                .layoutPriority(1)

            Spacer(minLength: 6)

            HStack(spacing: 5) {
                if session.state == .working {
                    WorkingDots()
                } else {
                    Circle()
                        .fill(stateColor)
                        .frame(width: 6, height: 6)
                }
                // While working, say what it is doing, such as "Editing ContentView.swift".
                if session.state == .working, let step = session.currentStep {
                    // Capped so a long step cannot crowd out the session name either.
                    Text(verbatim: step)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(stateColor)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .frame(width: AgentRowMetrics.statusWidth(for: session), alignment: .leading)
                } else {
                    Text(session.state.label)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(stateColor)
                        .lineLimit(1)
                }
            }
            .layoutPriority(2)

            Text(verbatim: relative(session.lastActivity))
                .font(.system(size: 10.5, weight: .medium).monospacedDigit())
                .foregroundStyle(.white.opacity(0.35))
                .frame(width: 30, alignment: .trailing)
        }
    }

    private var stateColor: Color {
        switch session.state {
        case .working: return Color(red: 0.45, green: 0.75, blue: 1.0)
        case .needsApproval: return .orange
        case .waiting: return .white.opacity(0.55)
        case .done: return Color(red: 0.2, green: 0.84, blue: 0.29)
        case .failed: return Color(red: 1.0, green: 0.36, blue: 0.32)
        }
    }

    private func relative(_ date: Date) -> String {
        let seconds = max(0, now.timeIntervalSince(date))
        if seconds < 60 { return "now" }
        if seconds < 3600 { return "\(Int(seconds / 60))m" }
        return "\(Int(seconds / 3600))h"
    }
}

private struct WorkingDots: View {
    @State private var phase = false

    var body: some View {
        HStack(spacing: 2) {
            ForEach(0..<3) { index in
                Circle()
                    .fill(Color(red: 0.45, green: 0.75, blue: 1.0))
                    .frame(width: 3.5, height: 3.5)
                    .opacity(phase ? 1 : 0.25)
                    .animation(.easeInOut(duration: 0.6).repeatForever().delay(Double(index) * 0.18), value: phase)
            }
        }
        .onAppear { phase = true }
    }
}

// MARK: - Output tab

private struct AudioOutputListView: View {
    @ObservedObject var manager: AudioOutputManager
    @State private var hoveredIndex: Int?

    var body: some View {
        if manager.devices.isEmpty {
            Text("No sound outputs")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.white.opacity(0.45))
                .frame(height: ExtrasPanelView.outputRowHeight)
        } else {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(manager.devices.prefix(6).enumerated()), id: \.element.id) { index, device in
                    let isCurrent = device.id == manager.defaultDeviceID
                    Button {
                        manager.select(device)
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: device.symbolName)
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(.white.opacity(isCurrent ? 0.95 : 0.55))
                                .frame(width: 18)
                            Text(verbatim: device.name)
                                .font(.system(size: 12, weight: isCurrent ? .semibold : .medium))
                                .foregroundStyle(.white.opacity(isCurrent ? 0.95 : 0.7))
                                .lineLimit(1)
                            Spacer(minLength: 4)
                            if isCurrent {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 10.5, weight: .bold))
                                    .foregroundStyle(Color(red: 0.45, green: 0.75, blue: 1.0))
                            }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .islandRow(height: ExtrasPanelView.outputRowHeight, isHighlighted: hoveredIndex == index)
                }
            }
            .islandRowHover(rowHeight: ExtrasPanelView.outputRowHeight, hoveredIndex: $hoveredIndex)
        }
    }
}

// MARK: - Note tab

private struct QuickNoteView: View {
    @ObservedObject var model: ExtrasPanelModel
    @FocusState private var isFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if model.isEditingNote {
                HStack(spacing: 8) {
                    TextField("Type a note, then press Return", text: $model.noteDraft)
                        .textFieldStyle(.plain)
                        .font(.system(size: 12.5, weight: .medium))
                        .foregroundStyle(.white)
                        .focused($isFocused)
                        .onSubmit { model.commitNote() }
                        .onExitCommand { model.cancelNote() }
                        .padding(.horizontal, 10)
                        .frame(height: 30)
                        .background(Color.white.opacity(0.1))
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

                    noteButton("checkmark", help: "Save") { model.commitNote() }
                }
                Text("Return saves · Esc cancels")
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(.white.opacity(0.35))
            } else {
                HStack(spacing: 8) {
                    Button {
                        model.beginEditingNote()
                    } label: {
                        Text(verbatim: model.noteText.isEmpty ? "Click to write a note" : model.noteText)
                            .font(.system(size: 12.5, weight: .medium))
                            .foregroundStyle(.white.opacity(model.noteText.isEmpty ? 0.4 : 0.92))
                            .lineLimit(1)
                            .truncationMode(.tail)
                            .padding(.horizontal, 10)
                            .frame(maxWidth: .infinity, minHeight: 30, alignment: .leading)
                            .background(Color.white.opacity(0.06))
                            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help(Text(verbatim: model.noteText.isEmpty ? "Write a note" : model.noteText))

                    if !model.noteText.isEmpty {
                        noteButton("doc.on.doc", help: "Copy") {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(model.noteText, forType: .string)
                        }
                        noteButton("xmark", help: "Clear") { model.clearNote() }
                    }
                }
                Text(model.noteText.isEmpty ? "Stays here until you clear it" : "Click to edit")
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(.white.opacity(0.35))
            }
        }
        .onChange(of: model.isEditingNote) { _, editing in
            guard editing else { return }
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(80))
                isFocused = true
            }
        }
    }

    private func noteButton(_ symbol: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(.white.opacity(0.7))
                .frame(width: 28, height: 28)
                .background(Color.white.opacity(0.08))
                .clipShape(Circle())
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help(help)
    }
}

// MARK: - Ask tab

private struct AskAIView: View {
    @ObservedObject var model: AskAIModel
    @FocusState private var isFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if model.hasConversation {
                conversation
            }
            inputRow
            if !model.hasConversation {
                Text("Answers come from ChatGPT on your subscription, through Codex")
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(.white.opacity(0.35))
            }
        }
        .onChange(of: model.isEditing) { _, editing in
            guard editing else { return }
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(80))
                isFocused = true
            }
        }
        .onDisappear { model.endEditing() }
    }

    @ViewBuilder
    private var conversation: some View {
        if SnapshotRendering.isActive {
            // Offscreen renders cannot draw a scroll view; lay the messages out as the app does.
            messageList
                .frame(height: ExtrasPanelView.askConversationHeight, alignment: .top)
                .clipped()
        } else {
            scrollingConversation
        }
    }

    private var messageList: some View {
        VStack(alignment: .leading, spacing: 5) {
            // An answer appears once its first words arrive.
            ForEach(model.messages.filter { !($0.role == .assistant && $0.text.isEmpty) }) { message in
                messageView(message)
                    // A question sits closer to its answer than to the answer before it.
                    .padding(.top, message.role == .user && message.id != model.messages.first?.id ? 9 : 0)
                    .id(message.id)
            }
            if model.isRunning && model.messages.last?.text.isEmpty != false {
                HStack(spacing: 6) {
                    ProgressView().controlSize(.mini).tint(.white)
                    Text("Thinking…")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.white.opacity(0.5))
                }
                .id("status")
            } else if let error = model.errorText {
                Text(error)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color(red: 1.0, green: 0.55, blue: 0.5))
                    .id("status")
            }
            Color.clear.frame(height: 1).id("end")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 2)
    }

    private var scrollingConversation: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical, showsIndicators: false) {
                messageList
            }
            .frame(height: ExtrasPanelView.askConversationHeight)
            .onChange(of: model.messages.count) { _, _ in scrollToEnd(proxy) }
            .onChange(of: model.isRunning) { _, _ in scrollToEnd(proxy) }
            // Follow the answer as it streams in.
            .onChange(of: model.messages.last?.text) { _, _ in
                if model.isRunning { proxy.scrollTo("end", anchor: .bottom) }
            }
            .onAppear { scrollToEnd(proxy) }
        }
    }

    private func scrollToEnd(_ proxy: ScrollViewProxy) {
        withAnimation(.easeOut(duration: 0.2)) {
            proxy.scrollTo("end", anchor: .bottom)
        }
    }

    @ViewBuilder
    private func messageView(_ message: AskAIModel.Message) -> some View {
        switch message.role {
        case .user:
            Text(verbatim: message.text)
                .font(.system(size: 11.5, weight: .semibold))
                .foregroundStyle(.white.opacity(0.5))
                .textSelection(.enabled)
        case .assistant:
            // Regular weight, so bold in an answer stands out.
            Text(Self.markdown(message.text))
                .font(.system(size: 12.5))
                .foregroundStyle(.white.opacity(0.92))
                .lineSpacing(2)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// Bold, italics, code and links render; anything else shows as typed.
    private static func markdown(_ text: String) -> AttributedString {
        (try? AttributedString(
            markdown: text,
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        )) ?? AttributedString(text)
    }

    private var inputRow: some View {
        HStack(spacing: 8) {
            if model.isEditing {
                TextField(model.messages.isEmpty ? "Ask anything, then press Return" : "Ask a follow-up", text: $model.draft)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundStyle(.white)
                    .focused($isFocused)
                    .onSubmit { model.send() }
                    .onExitCommand { model.endEditing() }
                    .padding(.horizontal, 10)
                    .frame(height: 30)
                    .background(Color.white.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            } else {
                Button {
                    model.beginEditing()
                } label: {
                    Text(verbatim: model.messages.isEmpty ? "Click to ask a question" : "Click to ask a follow-up")
                        .font(.system(size: 12.5, weight: .medium))
                        .foregroundStyle(.white.opacity(0.4))
                        .padding(.horizontal, 10)
                        .frame(maxWidth: .infinity, minHeight: 30, alignment: .leading)
                        .background(Color.white.opacity(0.06))
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }

            if model.isRunning {
                askButton("stop.fill", help: "Stop") { model.stop() }
            } else if model.isEditing && !model.draft.trimmingCharacters(in: .whitespaces).isEmpty {
                askButton("arrow.up", help: "Ask") { model.send() }
            } else if model.hasConversation {
                if let answer = model.lastAnswer {
                    askButton("doc.on.doc", help: "Copy the last answer") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(answer, forType: .string)
                    }
                }
                askButton("trash", help: "Start over") { model.clear() }
            }
        }
    }

    private func askButton(_ symbol: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(.white.opacity(0.7))
                .frame(width: 28, height: 28)
                .background(Color.white.opacity(0.08))
                .clipShape(Circle())
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help(help)
    }
}
