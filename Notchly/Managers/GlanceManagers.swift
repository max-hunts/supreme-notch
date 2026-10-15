//
//  GlanceManagers.swift
//  Notchly
//
//  Short informational islands: a download finished, a meeting is about to start,
//  AirPods connected. Each publishes through AgentEventManager.publishGlance so the
//  existing presentation and music handling are reused.
//

import AppKit
import Combine
import CoreAudio
import EventKit
import Foundation
import IOKit.ps

// MARK: - Downloads

@MainActor
final class DownloadGlanceManager {
    private let settingsManager: SettingsManager
    private let agentEventManager: AgentEventManager
    private var cancellables = Set<AnyCancellable>()
    private var source: DispatchSourceFileSystemObject?
    private var scanTask: Task<Void, Never>?
    private var progressTask: Task<Void, Never>?
    private var progressSubscriber: Any?
    private var announced = Set<String>()
    private var inFlight: [String: InFlight] = [:]
    /// Fractions published by browsers through NSProgress, keyed by file name.
    private var publishedFractions: [String: Double] = [:]
    private let fileManager = FileManager.default

    static let progressSource = "downloads-progress"

    private struct InFlight {
        let key: String
        let displayName: String
        let firstSeen: Date
        var lastBytes: Int64
        var lastSample: Date
        var bytesPerSecond: Double
        var presented: Bool
    }

    private static let partialExtensions: Set<String> = [
        "crdownload", "download", "part", "partial", "tmp", "opdownload", "filepart", "aria2", "!ut"
    ]

    init(settingsManager: SettingsManager, agentEventManager: AgentEventManager) {
        self.settingsManager = settingsManager
        self.agentEventManager = agentEventManager
    }

    func start() {
        settingsManager.$showDownloadGlance
            .combineLatest(settingsManager.$showDownloadProgress)
            .map { $0 || $1 }
            .removeDuplicates()
            .sink { [weak self] enabled in
                enabled ? self?.enable() : self?.disable()
            }
            .store(in: &cancellables)
    }

    func stop() {
        cancellables.removeAll()
        disable()
    }

    private var downloadsURL: URL? {
        fileManager.urls(for: .downloadsDirectory, in: .userDomainMask).first
    }

    private func enable() {
        guard source == nil, let downloadsURL else { return }

        // The first listing triggers the Downloads folder privacy prompt.
        announced = Set((try? fileManager.contentsOfDirectory(atPath: downloadsURL.path)) ?? [])

        let descriptor = open(downloadsURL.path, O_EVTONLY)
        guard descriptor >= 0 else { return }

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: descriptor,
            eventMask: [.write, .rename, .link],
            queue: .main
        )
        source.setEventHandler { [weak self] in
            MainActor.assumeIsolated {
                self?.scheduleScan()
            }
        }
        source.setCancelHandler {
            close(descriptor)
        }
        self.source = source
        source.resume()

        // Safari and Chromium browsers publish download progress for Finder's icon bars.
        progressSubscriber = Progress.addSubscriber(forFileURL: downloadsURL) { [weak self] progress in
            let name = (progress.userInfo[.fileURLKey] as? URL)?.lastPathComponent
            let observation = progress.observe(\.fractionCompleted, options: [.initial, .new]) { progress, _ in
                let fraction = progress.fractionCompleted
                DispatchQueue.main.async {
                    MainActor.assumeIsolated {
                        if let name { self?.publishedFractions[name] = fraction }
                    }
                }
            }
            return {
                observation.invalidate()
                DispatchQueue.main.async {
                    MainActor.assumeIsolated {
                        if let name { self?.publishedFractions.removeValue(forKey: name) }
                    }
                }
            }
        }

        scheduleScan()
    }

    private func disable() {
        source?.cancel()
        source = nil
        scanTask?.cancel()
        scanTask = nil
        progressTask?.cancel()
        progressTask = nil
        if let progressSubscriber {
            Progress.removeSubscriber(progressSubscriber)
        }
        progressSubscriber = nil
        for flight in inFlight.values {
            GlanceProgressStore.shared.remove(flight.key)
        }
        inFlight.removeAll()
        agentEventManager.dismissGlance(source: Self.progressSource)
    }

    private func scheduleScan() {
        scanTask?.cancel()
        scanTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(700))
            guard !Task.isCancelled else { return }
            await self?.scan()
        }
    }

    private func scan() async {
        guard let downloadsURL,
              let names = try? fileManager.contentsOfDirectory(atPath: downloadsURL.path) else { return }

        let nameSet = Set(names)
        // Forget names that disappeared so a re-download of the same name is announced.
        announced.formIntersection(nameSet)

        trackPartials(in: names, directory: downloadsURL)

        guard settingsManager.showDownloadGlance else { return }

        let candidates = names.filter { name in
            guard !announced.contains(name), !name.hasPrefix(".") else { return false }
            guard !Self.isPartial(name) else { return false }
            // Firefox keeps an empty placeholder next to "<name>.part" until the download ends.
            return !nameSet.contains(name + ".part") && !nameSet.contains(name + ".crdownload")
        }

        for name in candidates {
            let url = downloadsURL.appendingPathComponent(name)
            guard let first = fileSize(url), first > 0 else { continue }
            try? await Task.sleep(for: .milliseconds(1200))
            guard !Task.isCancelled else { return }
            guard let second = fileSize(url), second == first else { continue }
            guard let modified = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate,
                  Date().timeIntervalSince(modified) < 600 else {
                announced.insert(name)
                continue
            }

            announced.insert(name)
            agentEventManager.publishGlance(
                source: "downloads",
                title: "Downloaded \(ByteCountFormatter.string(fromByteCount: Int64(second), countStyle: .file))",
                detail: AgentToolSummarizer.truncate(name, limit: 70),
                style: AgentGlanceStyle(symbolName: "arrow.down.circle.fill", red: 0.38, green: 0.68, blue: 1.0),
                actionURL: url,
                ttl: 4
            )
        }
    }

    // MARK: Progress

    private static func isPartial(_ name: String) -> Bool {
        partialExtensions.contains((name as NSString).pathExtension.lowercased())
    }

    private func trackPartials(in names: [String], directory: URL) {
        let partials = Set(names.filter { !$0.hasPrefix(".") && Self.isPartial($0) })

        // Finished or cancelled downloads.
        for name in inFlight.keys where !partials.contains(name) {
            if let flight = inFlight.removeValue(forKey: name) {
                GlanceProgressStore.shared.remove(flight.key)
            }
        }
        if inFlight.isEmpty {
            // The finished glance (if any) replaces this; a cancelled download just disappears.
            Task { @MainActor [weak self] in
                try? await Task.sleep(for: .seconds(2.5))
                guard let self, self.inFlight.isEmpty else { return }
                self.agentEventManager.dismissGlance(source: Self.progressSource)
            }
        }

        guard settingsManager.showDownloadProgress else { return }

        let now = Date()
        for name in partials where inFlight[name] == nil {
            let url = directory.appendingPathComponent(name)
            inFlight[name] = InFlight(
                key: "download|\(name)",
                displayName: Self.displayName(forPartial: name),
                firstSeen: now,
                lastBytes: Self.partialSize(url),
                lastSample: now,
                bytesPerSecond: 0,
                presented: false
            )
        }

        if !inFlight.isEmpty, progressTask == nil {
            progressTask = Task { @MainActor [weak self] in
                while !Task.isCancelled {
                    try? await Task.sleep(for: .seconds(1))
                    guard let self, !Task.isCancelled else { return }
                    if !self.sampleProgress() {
                        self.progressTask = nil
                        return
                    }
                }
            }
        }
    }

    /// Updates live values. Returns false when nothing is downloading.
    private func sampleProgress() -> Bool {
        guard let downloadsURL, !inFlight.isEmpty else { return false }
        let now = Date()

        for (name, var flight) in inFlight {
            let url = downloadsURL.appendingPathComponent(name)
            guard fileManager.fileExists(atPath: url.path) else { continue }

            let bytes = Self.partialSize(url)
            let elapsed = now.timeIntervalSince(flight.lastSample)
            if elapsed > 0 {
                let instant = Double(max(0, bytes - flight.lastBytes)) / elapsed
                flight.bytesPerSecond = flight.bytesPerSecond == 0 ? instant : flight.bytesPerSecond * 0.6 + instant * 0.4
            }
            flight.lastBytes = bytes
            flight.lastSample = now

            let safari = Self.safariProgress(url)
            let stripped = (name as NSString).deletingPathExtension
            let fraction = publishedFractions[name] ?? publishedFractions[stripped] ?? safari.map { Double($0.done) / Double(max($0.total, 1)) }

            GlanceProgressStore.shared.update(flight.key, .init(
                fraction: fraction.map { min(max($0, 0), 1) },
                bytes: safari?.done ?? bytes,
                totalBytes: safari?.total,
                bytesPerSecond: flight.bytesPerSecond
            ))

            // Only big downloads earn an island: still running after 3 seconds.
            if !flight.presented, now.timeIntervalSince(flight.firstSeen) >= 3, bytes > 0 {
                flight.presented = true
                agentEventManager.publishGlance(
                    source: Self.progressSource,
                    title: "Downloading · click to hide",
                    detail: AgentToolSummarizer.truncate(flight.displayName, limit: 60),
                    style: AgentGlanceStyle(symbolName: "arrow.down", red: 0.38, green: 0.68, blue: 1.0),
                    actionURL: nil,
                    ttl: 15,
                    action: .dismiss,
                    progressKey: flight.key,
                    isSticky: true
                )
            }
            inFlight[name] = flight
        }
        return true
    }

    private static func displayName(forPartial name: String) -> String {
        let stripped = (name as NSString).deletingPathExtension
        if stripped.lowercased().hasPrefix("unconfirmed ") {
            return "New download"
        }
        return stripped
    }

    /// Size of a partial file, or of the payload inside a Safari .download bundle.
    private static func partialSize(_ url: URL) -> Int64 {
        let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .totalFileSizeKey, .fileSizeKey])
        if values?.isDirectory == true {
            let enumerator = FileManager.default.enumerator(at: url, includingPropertiesForKeys: [.totalFileSizeKey, .fileSizeKey])
            var total: Int64 = 0
            while let child = enumerator?.nextObject() as? URL {
                guard child.lastPathComponent != "Info.plist" else { continue }
                let childValues = try? child.resourceValues(forKeys: [.totalFileSizeKey, .fileSizeKey])
                total += Int64(childValues?.totalFileSize ?? childValues?.fileSize ?? 0)
            }
            return total
        }
        return Int64(values?.totalFileSize ?? values?.fileSize ?? 0)
    }

    /// Safari keeps bytes-so-far and total in the bundle's Info.plist.
    private static func safariProgress(_ url: URL) -> (done: Int64, total: Int64)? {
        guard url.pathExtension.lowercased() == "download",
              let data = try? Data(contentsOf: url.appendingPathComponent("Info.plist")),
              let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
              let done = (plist["DownloadEntryProgressBytesSoFar"] as? NSNumber)?.int64Value,
              let total = (plist["DownloadEntryProgressTotalToLoad"] as? NSNumber)?.int64Value,
              total > 0 else {
            return nil
        }
        return (done, total)
    }

    private func fileSize(_ url: URL) -> Int? {
        let values = try? url.resourceValues(forKeys: [.fileSizeKey, .totalFileSizeKey, .isDirectoryKey])
        if values?.isDirectory == true {
            return 1
        }
        return values?.totalFileSize ?? values?.fileSize
    }
}

// MARK: - Calendar

nonisolated struct UpcomingMeeting: Equatable {
    let title: String
    let start: Date
}

@MainActor
final class CalendarGlanceManager: ObservableObject {
    /// The next meeting starting within the reminder window, for the notch countdown.
    @Published private(set) var upcomingMeeting: UpcomingMeeting?

    private let settingsManager: SettingsManager
    private let agentEventManager: AgentEventManager
    private let store = EKEventStore()
    private var cancellables = Set<AnyCancellable>()
    private var timerTask: Task<Void, Never>?
    private var storeObserver: NSObjectProtocol?
    private var alerted = Set<String>()
    private var hasAccess = false
    /// End of the meeting whose reminder is up, so it can clear itself afterwards.
    private var shownReminderEnd: Date?

    init(settingsManager: SettingsManager, agentEventManager: AgentEventManager) {
        self.settingsManager = settingsManager
        self.agentEventManager = agentEventManager
    }

    func start() {
        settingsManager.$showCalendarGlance
            .removeDuplicates()
            .sink { [weak self] enabled in
                enabled ? self?.enable() : self?.disable()
            }
            .store(in: &cancellables)
    }

    func stop() {
        cancellables.removeAll()
        disable()
    }

    private func enable() {
        guard timerTask == nil else { return }

        Task { @MainActor [weak self] in
            guard let self else { return }
            let granted = (try? await self.store.requestFullAccessToEvents()) ?? false
            self.hasAccess = granted
            guard granted, self.settingsManager.showCalendarGlance, self.timerTask == nil else { return }

            self.storeObserver = NotificationCenter.default.addObserver(
                forName: .EKEventStoreChanged,
                object: self.store,
                queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.check()
                }
            }

            self.timerTask = Task { @MainActor [weak self] in
                while !Task.isCancelled {
                    self?.check()
                    try? await Task.sleep(for: .seconds(30))
                }
            }
        }
    }

    private func disable() {
        timerTask?.cancel()
        timerTask = nil
        upcomingMeeting = nil
        if let storeObserver {
            NotificationCenter.default.removeObserver(storeObserver)
        }
        storeObserver = nil
    }

    private func check() {
        guard hasAccess else { return }

        let now = Date()
        if let end = shownReminderEnd, now >= end {
            shownReminderEnd = nil
            agentEventManager.dismissGlance(source: "calendar")
        }

        let lead = max(1, settingsManager.calendarLeadMinutes) * 60
        let excluded = Set(settingsManager.calendarExcludedIDs)
        let calendars = store.calendars(for: .event).filter { !excluded.contains($0.calendarIdentifier) }
        guard !calendars.isEmpty else {
            if upcomingMeeting != nil { upcomingMeeting = nil }
            return
        }
        let predicate = store.predicateForEvents(
            withStart: now.addingTimeInterval(-60),
            end: now.addingTimeInterval(lead + 60),
            calendars: calendars
        )

        let events = store.events(matching: predicate)
            .filter { !$0.isAllDay && $0.status != .canceled && !Self.isDeclined($0) }
            .sorted { $0.startDate < $1.startDate }

        let next = events.first { $0.startDate > now && $0.startDate.timeIntervalSince(now) <= lead }
        let meeting = next.map {
            UpcomingMeeting(
                title: $0.title?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty ?? "Meeting",
                start: $0.startDate
            )
        }
        if meeting != upcomingMeeting {
            upcomingMeeting = meeting
        }

        for event in events {
            let secondsUntil = event.startDate.timeIntervalSince(now)
            let key = "\(event.calendarItemIdentifier)|\(event.startDate.timeIntervalSince1970)"

            let phase: String
            if secondsUntil <= 45 && secondsUntil > -60 {
                phase = "start"
            } else if secondsUntil <= lead && secondsUntil > 45 {
                phase = "lead"
            } else {
                continue
            }

            guard !alerted.contains("\(key)|\(phase)") else { continue }
            alerted.insert("\(key)|\(phase)")
            if phase == "start" {
                alerted.insert("\(key)|lead")
            }

            let minutes = Int((secondsUntil / 60).rounded(.up))
            let title = phase == "start" ? "Starting now" : "In \(minutes) min"
            let joinURL = Self.joinURL(for: event)
            let name = event.title?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty ?? "Event"

            var buttons: [GlanceButton] = []
            if let joinURL {
                buttons.append(GlanceButton(title: "Join", systemImage: "video.fill", isPrimary: true, action: .open(joinURL)))
            } else if let calendarURL = URL(string: "ical://") {
                buttons.append(GlanceButton(title: "Calendar", systemImage: "calendar", isPrimary: false, action: .open(calendarURL)))
            }
            buttons.append(GlanceButton(title: "Dismiss", systemImage: "xmark", isPrimary: false, action: .dismiss))

            // "Starting now" replaces the earlier reminder for the same meeting.
            agentEventManager.dismissGlance(source: "calendar")
            shownReminderEnd = event.endDate
            agentEventManager.publishGlance(
                source: "calendar",
                title: title,
                detail: AgentToolSummarizer.truncate(name, limit: 80),
                style: AgentGlanceStyle(symbolName: "calendar", red: 1.0, green: 0.42, blue: 0.4),
                actionURL: nil,
                ttl: 15,
                isSticky: true,
                buttons: buttons
            )
            break
        }

        if alerted.count > 500 {
            alerted.removeAll()
        }
    }

    private static func isDeclined(_ event: EKEvent) -> Bool {
        event.attendees?.first(where: { $0.isCurrentUser })?.participantStatus == .declined
    }

    private static let joinPattern = try? NSRegularExpression(
        pattern: #"https?://[^\s<>"']*(zoom\.us/(j|my|w)/|meet\.google\.com/|teams\.microsoft\.com/l/meetup-join|teams\.live\.com/meet|webex\.com/|whereby\.com/|meet\.around\.co/|app\.slack\.com/huddle)[^\s<>"']*"#,
        options: [.caseInsensitive]
    )

    static func joinURL(for event: EKEvent) -> URL? {
        let candidates = [event.url?.absoluteString, event.location, event.notes].compactMap { $0 }
        for text in candidates {
            let range = NSRange(text.startIndex..., in: text)
            if let match = joinPattern?.firstMatch(in: text, range: range),
               let swiftRange = Range(match.range, in: text) {
                return URL(string: String(text[swiftRange]))
            }
        }
        return nil
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}

// MARK: - AirPods and Bluetooth headphones

@MainActor
final class AirPodsGlanceManager {
    private let settingsManager: SettingsManager
    private let agentEventManager: AgentEventManager
    private var cancellables = Set<AnyCancellable>()
    private var knownBluetoothDevices = Set<String>()
    private var listenerBlock: AudioObjectPropertyListenerBlock?
    private var lookupTask: Task<Void, Never>?

    init(settingsManager: SettingsManager, agentEventManager: AgentEventManager) {
        self.settingsManager = settingsManager
        self.agentEventManager = agentEventManager
    }

    func start() {
        settingsManager.$showAirPodsGlance
            .removeDuplicates()
            .sink { [weak self] enabled in
                enabled ? self?.enable() : self?.disable()
            }
            .store(in: &cancellables)
    }

    func stop() {
        cancellables.removeAll()
        disable()
    }

    private func enable() {
        guard listenerBlock == nil else { return }
        knownBluetoothDevices = Set(Self.bluetoothAudioDeviceNames())

        let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    self?.devicesChanged()
                }
            }
        }
        var address = Self.devicesAddress
        let status = AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &address, .main, block)
        if status == noErr {
            listenerBlock = block
        }
    }

    private func disable() {
        if let listenerBlock {
            var address = Self.devicesAddress
            AudioObjectRemovePropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &address, .main, listenerBlock)
        }
        listenerBlock = nil
        lookupTask?.cancel()
        lookupTask = nil
    }

    private func devicesChanged() {
        let current = Set(Self.bluetoothAudioDeviceNames())
        let added = current.subtracting(knownBluetoothDevices)
        knownBluetoothDevices = current
        guard let name = added.first else { return }

        lookupTask?.cancel()
        lookupTask = Task { @MainActor [weak self] in
            // Battery levels are published a moment after the audio route appears.
            var parts: [GlanceBatteryPart] = []
            for delay in [1.0, 2.0, 3.0] {
                try? await Task.sleep(for: .seconds(delay))
                guard !Task.isCancelled else { return }
                parts = AccessoryBatteryReader.parts(forDeviceNamed: name)
                if !parts.isEmpty { break }
            }
            guard !Task.isCancelled else { return }
            self?.announce(name: name, parts: parts)
        }
    }

    private func announce(name: String, parts: [GlanceBatteryPart]) {
        agentEventManager.publishGlance(
            source: "airpods",
            title: "Connected",
            detail: name,
            style: AgentGlanceStyle(symbolName: Self.deviceSymbol(for: name), red: 0.9, green: 0.9, blue: 0.95),
            actionURL: URL(string: "x-apple.systempreferences:com.apple.BluetoothSettings"),
            ttl: 5,
            batteryParts: parts
        )
    }

    nonisolated static func deviceSymbol(for name: String) -> String {
        let lower = name.lowercased()
        if lower.contains("airpods max") { return "airpodsmax" }
        if lower.contains("airpods pro") { return "airpodspro" }
        if lower.contains("airpods") { return "airpods" }
        if lower.contains("beats") { return "beats.headphones" }
        return "headphones"
    }

    private static var devicesAddress = AudioObjectPropertyAddress(
        mSelector: kAudioHardwarePropertyDevices,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain
    )

    private static func bluetoothAudioDeviceNames() -> [String] {
        var address = devicesAddress
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size) == noErr else { return [] }

        var ids = [AudioDeviceID](repeating: 0, count: Int(size) / MemoryLayout<AudioDeviceID>.size)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &ids) == noErr else { return [] }

        return ids.compactMap { id in
            var transport: UInt32 = 0
            var transportSize = UInt32(MemoryLayout<UInt32>.size)
            var transportAddress = AudioObjectPropertyAddress(
                mSelector: kAudioDevicePropertyTransportType,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain
            )
            guard AudioObjectGetPropertyData(id, &transportAddress, 0, nil, &transportSize, &transport) == noErr,
                  transport == kAudioDeviceTransportTypeBluetooth || transport == kAudioDeviceTransportTypeBluetoothLE else {
                return nil
            }

            var name: Unmanaged<CFString>?
            var nameSize = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
            var nameAddress = AudioObjectPropertyAddress(
                mSelector: kAudioObjectPropertyName,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain
            )
            guard AudioObjectGetPropertyData(id, &nameAddress, 0, nil, &nameSize, &name) == noErr,
                  let value = name?.takeRetainedValue() as String? else {
                return nil
            }
            return value
        }
    }
}

/// Reads accessory batteries from the power-sources service that feeds the macOS
/// battery widget and `pmset -g accps`. No Bluetooth permission is needed.
nonisolated enum AccessoryBatteryReader {
    private typealias CopyByType = @convention(c) (Int32) -> Unmanaged<CFTypeRef>?

    private static let copyPowerSourcesByType: CopyByType? = {
        guard let handle = dlopen("/System/Library/Frameworks/IOKit.framework/IOKit", RTLD_NOW),
              let symbol = dlsym(handle, "IOPSCopyPowerSourcesByType") else { return nil }
        return unsafeBitCast(symbol, to: CopyByType.self)
    }()

    static func allAccessorySources() -> [[String: Any]] {
        // Type 0 includes accessory sources; the public IOPSCopyPowerSourcesInfo omits them.
        guard let info = copyPowerSourcesByType?(0)?.takeRetainedValue() else { return [] }
        let list = IOPSCopyPowerSourcesList(info).takeRetainedValue() as Array
        return list.compactMap { source in
            guard let description = IOPSGetPowerSourceDescription(info, source)?.takeUnretainedValue() as? [String: Any],
                  description["Type"] as? String == "Accessory Source" else { return nil }
            return description
        }
    }

    static func parts(forDeviceNamed name: String) -> [GlanceBatteryPart] {
        parts(forDeviceNamed: name, in: allAccessorySources())
    }

    static func parts(forDeviceNamed name: String, in sources: [[String: Any]]) -> [GlanceBatteryPart] {
        let target = normalized(name)
        let matches = sources.filter { source in
            guard let sourceName = source["Name"] as? String else { return false }
            let candidate = normalized(sourceName)
            return candidate == target || target.hasSuffix(candidate) || candidate.hasSuffix(target)
        }
        guard let primary = matches.first(where: { ($0["Part Identifier"] as? String) != "Case" }) ?? matches.first else {
            return []
        }

        // The case is its own source, linked to the buds by Group Identifier.
        var related = [primary]
        if let group = primary["Group Identifier"] as? String {
            related += sources.filter { ($0["Group Identifier"] as? String) == group && !NSDictionary(dictionary: $0).isEqual(to: primary) }
        }

        var parts: [GlanceBatteryPart] = []
        for source in related {
            let identifier = source["Part Identifier"] as? String ?? "Single"
            if identifier == "Combined", let combined = source["Combined Parts"] as? [[String: Any]] {
                parts += combined.compactMap(part)
            } else if let single = part(from: source) {
                parts.append(single)
            }
        }

        let order: [GlanceBatteryPart.Kind] = [.left, .right, .single, .case]
        return parts.sorted { order.firstIndex(of: $0.kind)! < order.firstIndex(of: $1.kind)! }
    }

    private static func part(from source: [String: Any]) -> GlanceBatteryPart? {
        guard let level = source["Current Capacity"] as? Int else { return nil }
        let kind: GlanceBatteryPart.Kind
        switch source["Part Identifier"] as? String {
        case "Left": kind = .left
        case "Right": kind = .right
        case "Case": kind = .case
        default: kind = .single
        }
        return GlanceBatteryPart(kind: kind, level: min(max(level, 0), 100), isCharging: (source["Is Charging"] as? Bool) ?? ((source["Is Charging"] as? Int) == 1))
    }

    private static func normalized(_ text: String) -> String {
        text.replacingOccurrences(of: "\u{2019}", with: "'")
            .lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
