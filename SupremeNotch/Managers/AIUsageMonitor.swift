//
//  AIUsageMonitor.swift
//  SupremeNotch
//
//  Claude and Codex plan usage (5-hour, 7-day, per-model and Codex weekly windows) from
//  claude-usage-monitor, the Rust tool bundled in Contents/Helpers (falling back to an
//  installed copy). SupremeNotch runs `claude-usage-monitor --json` and reads
//  its output. Credentials come from that tool's config, or from keys saved in SupremeNotch's
//  Settings (kept in the Keychain and passed to the tool for that run only). It only
//  runs while the Usage tab is on screen.
//

import Combine
import Foundation

/// Which limit a usage window is, so each can be shown or hidden on its own.
nonisolated enum UsageLimitKind: String, CaseIterable, Identifiable, Sendable {
    case fiveHour, weekly, modelWeekly, codexFiveHour, codexWeekly

    var isCodex: Bool { self == .codexFiveHour || self == .codexWeekly }

    var id: String { rawValue }

    var title: String {
        switch self {
        case .fiveHour: return "5-hour"
        case .weekly: return "Weekly"
        case .modelWeekly: return "Fable weekly"
        case .codexFiveHour: return "Codex 5-hour"
        case .codexWeekly: return "Codex weekly"
        }
    }
}

nonisolated struct UsageWindow: Equatable, Identifiable {
    var id: String { label }
    let label: String
    var kind: UsageLimitKind = .weekly
    /// Percent of the window used, 0 to 100+.
    let percent: Double
    let resetsAt: Date?

    /// How long the window runs: five hours or a week.
    var duration: TimeInterval {
        kind == .fiveHour || kind == .codexFiveHour ? 5 * 3600 : 7 * 86400
    }

    /// The share of the window already gone, 0 to 1. Nil when the reset time is unknown,
    /// as for a 5-hour window with no session running.
    func elapsed(at now: Date = Date()) -> Double? {
        guard let resetsAt else { return nil }
        return min(max(1 - resetsAt.timeIntervalSince(now) / duration, 0), 1)
    }
}

nonisolated struct AIUsageSnapshot: Equatable {
    var claude: [UsageWindow] = []
    /// Codex's weekly window.
    var codex: UsageWindow?
    /// Codex's rolling 5-hour window; only some plans have one.
    var codexFiveHour: UsageWindow?
    var claudeError: String?
    var codexError: String?
    var fetchedAt = Date()


    /// Parses `claude-usage-monitor --json`. Nil when the output is not that shape.
    static func parse(_ data: Data) -> AIUsageSnapshot? {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        var snapshot = AIUsageSnapshot()

        func window(_ object: Any?, label: String, kind: UsageLimitKind, percentKey: String = "utilization") -> UsageWindow? {
            guard let dict = object as? [String: Any],
                  let percent = (dict[percentKey] as? NSNumber)?.doubleValue else { return nil }
            return UsageWindow(label: label, kind: kind, percent: percent, resetsAt: date(dict["resets_at"]))
        }

        if let five = window(root["five_hour"], label: "5 hours", kind: .fiveHour) { snapshot.claude.append(five) }
        if let seven = window(root["seven_day"], label: "Week", kind: .weekly) { snapshot.claude.append(seven) }
        // Model-scoped weekly caps, such as a Fable-only limit.
        for limit in root["limits"] as? [[String: Any]] ?? [] where limit["kind"] as? String == "weekly_scoped" {
            let scope = limit["scope"] as? [String: Any]
            let model = (scope?["model"] as? [String: Any])?["display_name"] as? String
            if let scoped = window(limit, label: model ?? "Model week", kind: .modelWeekly, percentKey: "percent") {
                snapshot.claude.append(scoped)
            }
        }
        snapshot.claudeError = (root["claude_error"] as? String).flatMap(Self.shortError)

        if let codex = root["codex"] as? [String: Any] {
            let hasFiveHour = codex["five_hour"] is [String: Any]
            snapshot.codexFiveHour = window(codex["five_hour"], label: "Codex 5h", kind: .codexFiveHour)
            // Just "Codex" when the plan has only the weekly window, as before.
            snapshot.codex = window(codex["weekly"], label: hasFiveHour ? "Codex wk" : "Codex", kind: .codexWeekly)
            snapshot.codexError = (codex["error"] as? String).flatMap(Self.shortError)
        }

        guard !snapshot.claude.isEmpty || !snapshot.codexWindows.isEmpty
                || snapshot.claudeError != nil || snapshot.codexError != nil else {
            return nil
        }
        return snapshot
    }

    /// Codex's windows in display order: 5-hour, then weekly.
    var codexWindows: [UsageWindow] {
        [codexFiveHour, codex].compactMap { $0 }
    }

    private static func date(_ value: Any?) -> Date? {
        guard let text = value as? String else { return nil }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: text) { return date }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: text)
    }

    /// Nil for a provider that has no keys at all: it is simply not shown, so a Codex-only
    /// or Claude-only setup has no error row for the other.
    private static func shortError(_ text: String) -> String? {
        let line = text.trimmingCharacters(in: .whitespacesAndNewlines)
            .components(separatedBy: .newlines).first ?? ""
        guard !line.isEmpty else { return nil }
        if line.lowercased().contains("not configured") {
            return nil
        }
        if line.contains("401") || line.contains("403") || line.lowercased().contains("forbidden") {
            return "Sign-in expired. Update the keys in Settings → AI Usage."
        }
        return String(line.prefix(80))
    }
}

@MainActor
final class AIUsageMonitor: ObservableObject {
    enum State: Equatable {
        case idle
        case notInstalled
        case loaded(AIUsageSnapshot)
        case failed(String)
    }

    @Published private(set) var state: State = .idle
    @Published private(set) var isFetching = false

    private var liveTask: Task<Void, Never>?
    private var liveCount = 0
    private static let interval: Duration = .seconds(15)
    nonisolated private static let timeout: TimeInterval = 20

    /// Rows in the Usage tab: one per window, or one line before the first reading.
    var rowCount: Int {
        guard case let .loaded(snapshot) = state else { return 1 }
        let claudeRows = snapshot.claude.isEmpty ? (snapshot.claudeError == nil ? 0 : 1) : snapshot.claude.count
        let codexRows = snapshot.codexWindows.isEmpty ? (snapshot.codexError == nil ? 0 : 1) : snapshot.codexWindows.count
        return max(1, claudeRows + codexRows)
    }

    /// The copy bundled inside SupremeNotch first, then where cargo and Homebrew install it.
    nonisolated static func binaryURL() -> URL? {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let bundled = Bundle.main.bundleURL.appendingPathComponent("Contents/Helpers/claude-usage-monitor").path
        let candidates = [
            bundled,
            "\(home)/.cargo/bin/claude-usage-monitor",
            "/opt/homebrew/bin/claude-usage-monitor",
            "/usr/local/bin/claude-usage-monitor"
        ]
        return candidates.first { FileManager.default.isExecutableFile(atPath: $0) }.map(URL.init(fileURLWithPath:))
    }

    /// Refreshes while the Usage tab is on screen.
    func startLive() {
        liveCount += 1
        guard liveTask == nil else { return }
        liveTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                await self?.fetch()
                try? await Task.sleep(for: Self.interval)
            }
        }
    }

    func stopLive() {
        liveCount = max(0, liveCount - 1)
        guard liveCount == 0 else { return }
        liveTask?.cancel()
        liveTask = nil
    }

    private var backgroundTask: Task<Void, Never>?
    private static let backgroundInterval: Duration = .seconds(300)

    /// A slow refresh for the usage bars in the closed notch.
    func startBackground() {
        guard backgroundTask == nil else { return }
        backgroundTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                await self?.fetch()
                try? await Task.sleep(for: Self.backgroundInterval)
            }
        }
    }

    func stopBackground() {
        backgroundTask?.cancel()
        backgroundTask = nil
    }

    /// Forces a fresh reading, for example after new keys are saved.
    func refreshNow() {
        Task { await fetch() }
    }

    func fetch() async {
        guard !isFetching else { return }
        guard let binary = Self.binaryURL() else {
            state = .notInstalled
            return
        }
        isFetching = true
        defer { isFetching = false }

        let result = await Task.detached(priority: .utility) { () -> Result<Data, Error> in
            Self.run(binary)
        }.value

        switch result {
        case let .success(data):
            if let snapshot = AIUsageSnapshot.parse(data) {
                state = .loaded(snapshot)
            } else if case .loaded = state {
                // Keep the last good reading through a bad poll.
            } else {
                state = .failed("Unexpected output from claude-usage-monitor")
            }
        case let .failure(error):
            if case .loaded = state { return }
            state = .failed(error.localizedDescription)
        }
    }

    private struct RunError: LocalizedError {
        let errorDescription: String?
    }

    nonisolated private static func run(_ binary: URL) -> Result<Data, Error> {
        let process = Process()
        process.executableURL = binary
        process.arguments = ["--json"]
        let output = Pipe()
        let errors = Pipe()
        process.standardOutput = output
        process.standardError = errors
        process.standardInput = FileHandle.nullDevice
        // Keys saved in SupremeNotch override the tool's own config, field by field.
        var environment = ProcessInfo.processInfo.environment
        environment.merge(UsageCredentialStore.environmentOverrides()) { _, saved in saved }
        process.environment = environment

        do {
            try process.run()
        } catch {
            return .failure(error)
        }

        let deadline = DispatchTime.now() + timeout
        let killer = DispatchWorkItem { if process.isRunning { process.terminate() } }
        DispatchQueue.global().asyncAfter(deadline: deadline, execute: killer)

        let data = output.fileHandleForReading.readDataToEndOfFile().prefix(1_000_000)
        let errorText = String(decoding: errors.fileHandleForReading.readDataToEndOfFile().prefix(2000), as: UTF8.self)
        process.waitUntilExit()
        killer.cancel()

        if process.terminationStatus != 0, data.isEmpty {
            let message = errorText.replacingOccurrences(of: "Error: ", with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .components(separatedBy: .newlines).first ?? ""
            if message.lowercased().contains("no credentials configured") {
                return .failure(RunError(errorDescription: "Add your Claude or Codex keys in Settings → AI Usage"))
            }
            return .failure(RunError(errorDescription: message.isEmpty ? "claude-usage-monitor exited with \(process.terminationStatus)" : String(message.prefix(100))))
        }
        return .success(Data(data))
    }

    #if DEBUG
    /// Sample data for README images.
    func previewLoad(_ snapshot: AIUsageSnapshot) { state = .loaded(snapshot) }
    #endif
}
