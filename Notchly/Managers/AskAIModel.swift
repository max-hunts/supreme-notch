//
//  AskAIModel.swift
//  BetterNotch
//
//  The Ask tab: a quick question-and-answer chat with ChatGPT's models on your ChatGPT
//  subscription, through the Codex command-line tool that ships with the ChatGPT app.
//  No API key and no API billing. Each question runs Codex as a bare chat: in an empty
//  private folder, read-only, with no MCP servers, plugins or hooks, and nothing saved to
//  Codex's history. Follow-ups continue the conversation by sending it along each time.
//

import AppKit
import Combine
import Foundation

@MainActor
final class AskAIModel: ObservableObject {
    nonisolated struct Message: Identifiable, Equatable, Sendable {
        enum Role: Sendable { case user, assistant }
        let id = UUID()
        let role: Role
        let text: String
    }

    @Published private(set) var messages: [Message] = []
    @Published var draft = ""
    @Published private(set) var isRunning = false
    @Published private(set) var errorText: String?
    @Published private(set) var isEditing = false

    private var process: Process?
    private var resignObserver: NSObjectProtocol?

    /// Gives up on an answer after this long.
    static let timeout: TimeInterval = 90
    /// How much earlier conversation goes along with a follow-up.
    static let historyLimit = 12

    var hasConversation: Bool { !messages.isEmpty || isRunning || errorText != nil }

    // MARK: Typing

    func beginEditing() {
        guard !isEditing else { return }
        isEditing = true
        IslandKeyFocus.begin()
        resignObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didResignKeyNotification,
            object: IslandKeyFocus.islandWindow,
            queue: .main
        ) { [weak self] _ in
            // Clicking into another app ends typing; the draft stays.
            MainActor.assumeIsolated { self?.endEditing() }
        }
    }

    func endEditing() {
        guard isEditing else { return }
        isEditing = false
        if let resignObserver {
            NotificationCenter.default.removeObserver(resignObserver)
        }
        resignObserver = nil
        IslandKeyFocus.end()
    }

    // MARK: Asking

    func send() {
        let question = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !question.isEmpty, !isRunning else { return }
        guard let codex = Self.codexURL() else {
            errorText = "Codex was not found. Install the ChatGPT app and sign in to Codex once."
            return
        }
        let prompt = Self.prompt(question: question, history: messages)
        messages.append(Message(role: .user, text: question))
        draft = ""
        errorText = nil
        isRunning = true

        let process = Self.makeProcess(codex: codex, prompt: prompt, folder: Self.workingDirectory)
        self.process = process
        Task.detached { [weak self] in
            let result = Self.run(process)
            await MainActor.run {
                guard let self, self.process === process else { return }
                self.process = nil
                self.isRunning = false
                switch result {
                case let .success(answer):
                    self.messages.append(Message(role: .assistant, text: answer))
                case let .failure(error):
                    self.errorText = error.message
                }
            }
        }
    }

    func stop() {
        guard let process else { return }
        self.process = nil
        if process.isRunning { process.terminate() }
        isRunning = false
        errorText = "Stopped."
    }

    func clear() {
        stop()
        messages.removeAll()
        errorText = nil
    }

    #if DEBUG
    /// Sample conversation for render checks.
    func previewLoad(_ exchange: [(question: String, answer: String)]) {
        messages = exchange.flatMap { [Message(role: .user, text: $0.question), Message(role: .assistant, text: $0.answer)] }
    }
    #endif

    var lastAnswer: String? {
        messages.last { $0.role == .assistant }?.text
    }

    // MARK: Codex

    /// The Codex inside the ChatGPT app comes first: it matches the app's own login.
    nonisolated static func codexURL() -> URL? {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let candidates = [
            "/Applications/ChatGPT.app/Contents/Resources/codex-cli/bin/codex",
            "\(home)/Applications/ChatGPT.app/Contents/Resources/codex-cli/bin/codex",
            "/opt/homebrew/bin/codex",
            "/usr/local/bin/codex",
            "\(home)/.local/bin/codex"
        ]
        return candidates.first { FileManager.default.isExecutableFile(atPath: $0) }.map(URL.init(fileURLWithPath:))
    }

    /// An empty folder of its own, so Codex never sees a project or a git repository.
    static var workingDirectory: URL {
        let url = AgentHookPaths.baseDirectoryURL.appendingPathComponent("ask-ai", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: url.path)
        return url
    }

    nonisolated static func prompt(question: String, history: [Message]) -> String {
        var text = """
        You are answering a quick question typed into a small panel in the Mac menu bar. \
        Reply directly and briefly, in American English. Use plain sentences, with a short list only when it helps. \
        Do not run commands, read files or use any tools; answer from what you know, and say \
        so when you are not sure.
        """
        let earlier = history.suffix(historyLimit)
        if !earlier.isEmpty {
            text += "\n\nConversation so far:\n"
            for message in earlier {
                text += (message.role == .user ? "User: " : "Assistant: ") + message.text + "\n"
            }
        }
        text += "\nQuestion: \(question)"
        return text
    }

    nonisolated private static func makeProcess(codex: URL, prompt: String, folder: URL) -> Process {
        let process = Process()
        process.executableURL = codex
        process.currentDirectoryURL = folder
        process.arguments = [
            "exec",
            "--skip-git-repo-check",
            "--sandbox", "read-only",
            "--ephemeral",
            "--json",
            "--color", "never",
            "--cd", folder.path,
            // A bare chat: none of your MCP servers, plugins, hooks or notifiers.
            "-c", "mcp_servers={}",
            "-c", "features.hooks=false",
            "-c", "features.plugins=false",
            "-c", "notify=[]",
            "-c", "model_reasoning_effort=low",
            prompt
        ]
        process.standardInput = FileHandle.nullDevice
        return process
    }

    nonisolated struct AskError: Error {
        let message: String
    }

    /// Runs Codex and returns its last message. Codex prints one JSON event per line.
    nonisolated private static func run(_ process: Process) -> Result<String, AskError> {
        let output = Pipe()
        let errors = Pipe()
        process.standardOutput = output
        process.standardError = errors
        do {
            try process.run()
        } catch {
            return .failure(AskError(message: "Could not start Codex: \(error.localizedDescription)"))
        }
        let killer = DispatchWorkItem { if process.isRunning { process.terminate() } }
        DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: killer)

        let data = output.fileHandleForReading.readDataToEndOfFile().prefix(2_000_000)
        let errorText = String(decoding: errors.fileHandleForReading.readDataToEndOfFile().prefix(4000), as: UTF8.self)
        process.waitUntilExit()
        killer.cancel()

        var answer: String?
        var failure: String?
        for line in String(decoding: data, as: UTF8.self).split(separator: "\n") {
            guard let event = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any],
                  let type = event["type"] as? String else { continue }
            switch type {
            case "item.completed":
                if let item = event["item"] as? [String: Any], item["type"] as? String == "agent_message",
                   let text = item["text"] as? String, !text.isEmpty {
                    answer = text
                }
            case "turn.failed", "error":
                let error = (event["error"] as? [String: Any])?["message"] as? String ?? event["message"] as? String
                failure = error ?? failure
            default:
                break
            }
        }

        if let answer { return .success(answer.trimmingCharacters(in: .whitespacesAndNewlines)) }
        if process.terminationReason == .uncaughtSignal {
            return .failure(AskError(message: "No answer within \(Int(timeout)) seconds."))
        }
        let firstErrorLine = errorText
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .first { !$0.isEmpty && !$0.hasPrefix("Reading additional input") }
        let message = failure ?? firstErrorLine ?? "Codex exited with \(process.terminationStatus)."
        if message.localizedCaseInsensitiveContains("login") || message.localizedCaseInsensitiveContains("auth") {
            return .failure(AskError(message: "Codex is not signed in. Open the ChatGPT app's Codex once, or run codex login."))
        }
        return .failure(AskError(message: String(message.prefix(200))))
    }
}
