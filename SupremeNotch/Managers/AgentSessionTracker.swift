//
//  AgentSessionTracker.swift
//  SupremeNotch
//
//  Follows Claude Code and Codex sessions from hook events: which project, what state,
//  and when they last did something. Nothing is stored on disk; prompts are never read.
//

import AppKit
import Combine
import Darwin
import Foundation

nonisolated struct AgentSession: Identifiable, Equatable {
    enum State: Equatable {
        case working
        case needsApproval
        case waiting
        case done
        case failed

        var label: String {
            switch self {
            case .working: return "Working"
            case .needsApproval: return "Needs approval"
            case .waiting: return "Waiting for you"
            case .done: return "Done"
            case .failed: return "Failed"
            }
        }
    }

    let id: String
    let source: String
    var project: String?
    /// The agent's own name for the conversation, when it keeps one (Codex threads).
    var title: String? = nil
    var pid: pid_t?
    var state: State
    /// When the current state began; a working session's elapsed time counts from here.
    var stateSince: Date
    /// What the agent is doing now, such as "Editing ContentView.swift". Nil between tools.
    var currentStep: String?
    var lastActivity: Date

    var sourceLabel: String {
        source == "codex" ? "Codex" : "Claude Code"
    }

    /// What the Agents tab and alerts call this session.
    var displayName: String {
        title ?? project ?? sourceLabel
    }

    /// The right side of an Agents row: what it is doing while working, else its state.
    var statusText: String {
        if state == .working, let currentStep { return currentStep }
        return state.label
    }
}

@MainActor
final class AgentSessionTracker: ObservableObject {
    @Published private(set) var sessions: [AgentSession] = []

    private var byID: [String: AgentSession] = [:]
    private var pruneTask: Task<Void, Never>?
    /// Codex names a thread after its first turn, so the title is looked up again until found.
    private var titleLookups: [String: Date] = [:]

    /// Sessions shown in the panel, most recent first.
    var visibleSessions: [AgentSession] {
        sessions
    }

    var activeCount: Int {
        sessions.filter { $0.state == .working || $0.state == .needsApproval || $0.state == .waiting }.count
    }

    func record(
        source: String,
        sessionID: String,
        hookEvent: String?,
        kind: AgentEventKind,
        toolName: String? = nil,
        stepHint: String? = nil,
        cwd: String?,
        pid: Int?
    ) {
        let now = Date()
        var session = byID[sessionID] ?? AgentSession(
            id: sessionID,
            source: source,
            project: nil,
            pid: nil,
            state: .working,
            stateSince: now,
            currentStep: nil,
            lastActivity: now
        )

        if let cwd, !cwd.isEmpty {
            let name = URL(fileURLWithPath: cwd).lastPathComponent
            let home = FileManager.default.homeDirectoryForCurrentUser.path
            session.project = (cwd == home || cwd == "/") ? nil : name
        }
        if let pid, pid > 1 {
            session.pid = pid_t(pid)
        }
        if source == "codex", session.title == nil,
           now.timeIntervalSince(titleLookups[sessionID] ?? .distantPast) > 5 {
            titleLookups[sessionID] = now
            session.title = Self.codexThreadName(for: sessionID)
        }
        session.lastActivity = now
        let previousState = session.state

        switch (kind, hookEvent ?? "") {
        case (_, "SessionEnd"):
            byID.removeValue(forKey: sessionID)
            titleLookups.removeValue(forKey: sessionID)
            publish()
            return
        case (.accessRequest, _):
            session.state = .needsApproval
        case (.waiting, _):
            session.state = .waiting
        case (.completed, _):
            session.state = .done
        case (.failed, _):
            session.state = .failed
        case (.clear, "PermissionDenied"), (.clear, "UserPromptSubmit"), (.clear, "PreToolUse"), (.clear, "PostToolUse"):
            session.state = .working
        default:
            break
        }

        if session.state != previousState || hookEvent == "UserPromptSubmit" {
            // A new prompt restarts the clock even if the session never left "working".
            session.stateSince = now
        }
        switch hookEvent {
        case "PreToolUse":
            session.currentStep = Self.stepText(toolName: toolName, hint: stepHint)
        case "UserPromptSubmit":
            session.currentStep = nil
        default:
            if session.state != .working {
                session.currentStep = nil
            }
        }

        byID[sessionID] = session
        publish()
        schedulePruning()
    }

    /// An approval answered from the notch puts the session back to work.
    func markWorking(sessionID: String?) {
        guard let sessionID, var session = byID[sessionID] else { return }
        if session.state != .working {
            session.stateSince = Date()
        }
        session.state = .working
        session.lastActivity = Date()
        byID[sessionID] = session
        publish()
    }

    /// Shows the session: the exact session in the Claude app when it runs there, otherwise
    /// the app or terminal that runs it. False when nothing could be shown.
    @discardableResult
    func open(sessionID: String, source: String) -> Bool {
        if let session = byID[sessionID] {
            activate(session)
            return true
        }
        switch source {
        case "claude": return ClaudeDesktopSessionLocator.open(cliSessionID: sessionID)
        case "codex": return Self.openCodexThread(sessionID, pid: nil)
        default: return false
        }
    }

    /// Brings the session to the front: the exact session in the Claude app when it runs
    /// there, otherwise the app or terminal that runs it.
    func activate(_ session: AgentSession) {
        if session.source == "claude", ClaudeDesktopSessionLocator.open(cliSessionID: session.id) {
            return
        }
        if session.source == "codex", Self.openCodexThread(session.id, pid: session.pid) {
            return
        }
        if let pid = session.pid, let app = Self.owningApplication(of: pid) {
            app.activate(options: [.activateAllWindows])
            return
        }
        let bundleIDs = session.source == "codex"
            ? ["com.openai.codex", "com.openai.chat"]
            : ["com.anthropic.claudefordesktop"]
        for bundleID in bundleIDs {
            if let app = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first {
                app.activate(options: [.activateAllWindows])
                return
            }
        }
    }

    /// Turns a tool name and the hook's hint ("file:Name.swift" or "cmd:npm test") into a
    /// short line for the Agents tab.
    nonisolated static func stepText(toolName: String?, hint: String?) -> String? {
        let tool = toolName ?? ""
        let lower = tool.lowercased()
        if let hint, hint.hasPrefix("file:") {
            let name = String(hint.dropFirst(5))
            guard !name.isEmpty else { return nil }
            switch lower {
            case "read": return "Reading \(name)"
            case "write": return "Writing \(name)"
            case "edit", "multiedit", "notebookedit", "apply_patch": return "Editing \(name)"
            default: return "\(tool.isEmpty ? "Using" : tool) \(name)"
            }
        }
        if let hint, hint.hasPrefix("cmd:") {
            // Codex sends file patches as a command that starts "*** Begin Patch".
            if hint.dropFirst(4).hasPrefix("***") || lower == "apply_patch" {
                return "Editing files"
            }
            // "/Users/me/.venv/bin/python3 build.py" reads better as "python3 build.py".
            let command = hint.dropFirst(4)
                .split(separator: " ")
                .map { word in word.contains("/") ? (word.split(separator: "/").last.map(String.init) ?? String(word)) : String(word) }
                .joined(separator: " ")
                .trimmingCharacters(in: .whitespaces)
            return command.isEmpty ? "Running a command" : "Running \(command)"
        }
        switch lower {
        case "": return nil
        case "bash", "shell", "local_shell", "exec_command": return "Running a command"
        case "grep", "glob", "ls": return "Searching files"
        case "read": return "Reading a file"
        case "edit", "multiedit", "write", "apply_patch": return "Editing files"
        case "webfetch": return "Reading a web page"
        case "websearch": return "Searching the web"
        case "task", "agent": return "Running a subagent"
        case "todowrite": return "Updating its plan"
        default:
            if lower.hasPrefix("mcp__") {
                let parts = tool.components(separatedBy: "__").filter { !$0.isEmpty }
                return "Using \(parts.count > 1 ? parts[1] : "a tool")"
            }
            return "Using \(tool)"
        }
    }

    private func publish() {
        sessions = byID.values.sorted { $0.lastActivity > $1.lastActivity }
    }

    private func schedulePruning() {
        guard pruneTask == nil else { return }
        pruneTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(30))
                guard let self else { return }
                self.prune()
                if self.byID.isEmpty {
                    self.pruneTask = nil
                    return
                }
            }
        }
    }

    private func prune() {
        let now = Date()
        let before = byID.count
        byID = byID.filter { _, session in
            // A session whose agent process has exited is gone.
            if let pid = session.pid, kill(pid, 0) != 0, errno == ESRCH {
                return false
            }
            let age = now.timeIntervalSince(session.lastActivity)
            switch session.state {
            case .done, .failed:
                return age < 30 * 60
            default:
                return age < 2 * 60 * 60
            }
        }
        if byID.count != before {
            publish()
        }
    }

    // MARK: - Process tree

    /// Walks up from the hook's parent process to the first regular app, such as
    /// Terminal, Warp, iTerm, Cursor, or the Claude and Codex desktop apps.
    /// Opens the exact thread in the ChatGPT app, whose Codex runs as a helper inside it.
    /// The hook's session ID is the thread ID. A Codex CLI running in a terminal returns
    /// false so the terminal is brought forward instead.
    static func openCodexThread(_ threadID: String, pid: pid_t?) -> Bool {
        let codexAppID = "com.openai.codex"
        if let pid, let app = owningApplication(of: pid), app.bundleIdentifier != codexAppID {
            return false
        }
        guard NSWorkspace.shared.urlForApplication(withBundleIdentifier: codexAppID) != nil,
              !threadID.isEmpty,
              threadID.allSatisfy({ $0.isHexDigit || $0 == "-" }),
              let url = URL(string: "codex://threads/\(threadID)") else { return false }
        return NSWorkspace.shared.open(url)
    }

    /// Codex keeps each thread's title in ~/.codex/session_index.jsonl. The ChatGPT app's
    /// working folder is only a slug of the first message, so the title reads better.
    nonisolated static func codexThreadName(for threadID: String) -> String? {
        let url = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".codex/session_index.jsonl")
        guard let size = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? NSNumber)?.intValue,
              size <= 4_000_000,
              let text = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        var name: String?
        // Later lines win: a thread is re-listed when it is renamed.
        for line in text.split(separator: "\n") where line.contains(threadID) {
            guard let object = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any],
                  object["id"] as? String == threadID,
                  let title = (object["thread_name"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !title.isEmpty else { continue }
            name = title
        }
        return name
    }

    nonisolated static func owningApplication(of pid: pid_t) -> NSRunningApplication? {
        var current = pid
        for _ in 0..<12 {
            guard current > 1 else { return nil }
            if let app = NSRunningApplication(processIdentifier: current), app.activationPolicy == .regular {
                return app
            }
            guard let parent = parentPID(of: current), parent != current else { return nil }
            current = parent
        }
        return nil
    }

    nonisolated private static func parentPID(of pid: pid_t) -> pid_t? {
        var info = proc_bsdinfo()
        let size = Int32(MemoryLayout<proc_bsdinfo>.size)
        guard proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, size) == size else { return nil }
        return pid_t(info.pbi_ppid)
    }

    #if DEBUG
    /// Sample data for README images.
    func previewLoad(_ sessions: [AgentSession]) { self.sessions = sessions }
    #endif
}
