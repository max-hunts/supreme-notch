//
//  AskAIModel.swift
//  BetterNotch
//
//  The Ask tab: a quick question-and-answer chat with ChatGPT's models on your ChatGPT
//  subscription, through the Codex that ships with the ChatGPT app. No API key and no API
//  billing. A Codex app-server runs while you chat and streams each answer as it is
//  written. It is a bare chat: an empty private folder, read-only, no approvals, with no
//  MCP servers, plugins or hooks, and a temporary thread that is not saved to Codex's
//  history. Follow-ups continue the same thread.
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
        var text: String
    }

    @Published private(set) var messages: [Message] = []
    @Published var draft = ""
    @Published private(set) var isRunning = false
    @Published private(set) var errorText: String?
    @Published private(set) var isEditing = false

    private var server: CodexAppServer?
    private var threadID: String?
    /// A question waiting for the server to finish starting.
    private var queuedQuestion: String?
    private var nextRequestID = 100
    private var timeoutTask: Task<Void, Never>?
    private var idleTask: Task<Void, Never>?
    private var resignObserver: NSObjectProtocol?

    /// Gives up on an answer after this long.
    static let timeout: Duration = .seconds(90)
    /// The app-server quits after this long without a question.
    static let idleLimit: Duration = .seconds(600)
    /// How much earlier conversation a new thread is given when the old one has gone.
    static let historyLimit = 12

    static let instructions = """
    You are answering quick questions typed into a small panel in the Mac menu bar. \
    Reply directly and briefly, in American English. Use plain sentences, with a short list \
    only when it helps. Do not run commands, read files or use any tools; answer from what \
    you know, and say so when you are not sure.
    """

    init() {
        // Writing to an app-server that has just quit must not end BetterNotch.
        signal(SIGPIPE, SIG_IGN)
    }

    var hasConversation: Bool { !messages.isEmpty || isRunning || errorText != nil }

    var lastAnswer: String? {
        messages.last { $0.role == .assistant && !$0.text.isEmpty }?.text
    }

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
        errorText = nil

        // A new thread only knows what it is told, so it gets the earlier exchange.
        let text = threadID == nil ? Self.prompt(question: question, history: messages) : question
        messages.append(Message(role: .user, text: question))
        messages.append(Message(role: .assistant, text: ""))
        draft = ""
        isRunning = true
        idleTask?.cancel()
        startTimeout()

        if let server, server.isRunning, let threadID {
            startTurn(text, threadID: threadID, on: server)
        } else {
            queuedQuestion = text
            startServer()
        }
    }

    /// Ends the answer in progress. The server goes with it; the next question starts a
    /// new thread that is given the conversation so far.
    func stop() {
        guard isRunning else { return }
        shutDown()
        finish(error: "Stopped.")
    }

    func clear() {
        shutDown()
        timeoutTask?.cancel()
        isRunning = false
        messages.removeAll()
        errorText = nil
    }

    // MARK: App-server

    private func startServer() {
        let pending = queuedQuestion
        shutDown()
        queuedQuestion = pending
        guard let codex = Self.codexURL() else {
            finish(error: "Codex was not found. Install the ChatGPT app and sign in to Codex once.")
            return
        }
        let server = CodexAppServer(codex: codex, folder: Self.workingDirectory)
        server.onLine = { [weak self] line in self?.handle(line) }
        server.onExit = { [weak self, weak server] in
            guard let self, let server, self.server === server else { return }
            self.server = nil
            self.threadID = nil
            if self.isRunning { self.finish(error: "Codex stopped unexpectedly.") }
        }
        do {
            try server.start()
        } catch {
            finish(error: "Could not start Codex: \(error.localizedDescription)")
            return
        }
        self.server = server
        server.send(["id": 1, "method": "initialize", "params": [
            "clientInfo": ["name": "betternotch", "title": "BetterNotch", "version": Self.appVersion],
            "capabilities": NSNull()
        ]])
    }

    private func startTurn(_ text: String, threadID: String, on server: CodexAppServer) {
        nextRequestID += 1
        server.send(["id": nextRequestID, "method": "turn/start", "params": [
            "threadId": threadID,
            "input": [["type": "text", "text": text, "text_elements": [Any]()]]
        ]])
    }

    private func handle(_ line: Data) {
        guard let message = try? JSONSerialization.jsonObject(with: line) as? [String: Any] else { return }
        let id = message["id"] as? Int
        let method = message["method"] as? String

        // A request from Codex, such as an approval. This chat allows nothing.
        if let id, method != nil {
            server?.send(["id": id, "error": ["code": -32601, "message": "Not available in this chat"]])
            return
        }
        if id != nil, let error = message["error"] as? [String: Any] {
            if isRunning {
                finish(error: Self.friendly(error["message"] as? String ?? "Codex returned an error."))
            }
            return
        }
        if id == 1 {
            server?.send(["method": "initialized"])
            server?.send(["id": 2, "method": "thread/start", "params": [
                "cwd": Self.workingDirectory.path,
                "sandbox": "read-only",
                "approvalPolicy": "never",
                "ephemeral": true,
                "developerInstructions": Self.instructions
            ]])
            return
        }
        if id == 2 {
            guard let result = message["result"] as? [String: Any],
                  let thread = result["thread"] as? [String: Any],
                  let threadID = thread["id"] as? String, let server else {
                finish(error: "Codex did not start a conversation.")
                return
            }
            self.threadID = threadID
            if let queuedQuestion {
                self.queuedQuestion = nil
                startTurn(queuedQuestion, threadID: threadID, on: server)
            }
            return
        }

        let params = message["params"] as? [String: Any] ?? [:]
        switch method {
        case "item/agentMessage/delta":
            guard isRunning, let delta = params["delta"] as? String,
                  messages.last?.role == .assistant else { return }
            messages[messages.count - 1].text += delta
        case "error":
            let error = params["error"] as? [String: Any]
            if isRunning, params["willRetry"] as? Bool != true {
                finish(error: Self.friendly(error?["message"] as? String ?? "Codex returned an error."))
            }
        case "turn/completed":
            guard isRunning else { return }
            let turn = params["turn"] as? [String: Any]
            let status = turn?["status"] as? String
            let turnError = (turn?["error"] as? [String: Any])?["message"] as? String
            if status == "failed" || lastAnswerIsEmpty {
                finish(error: Self.friendly(turnError ?? "No answer came back."))
            } else {
                finish(error: nil)
            }
        default:
            break
        }
    }

    private var lastAnswerIsEmpty: Bool {
        messages.last.map { $0.role == .assistant && $0.text.isEmpty } ?? true
    }

    private func finish(error: String?) {
        timeoutTask?.cancel()
        timeoutTask = nil
        queuedQuestion = nil
        if let error {
            errorText = error
            // Drop an answer that never started, so the question stands on its own.
            if lastAnswerIsEmpty, messages.last?.role == .assistant { messages.removeLast() }
        }
        isRunning = false
        scheduleIdleShutdown()
    }

    private func startTimeout() {
        timeoutTask?.cancel()
        timeoutTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: Self.timeout)
            guard !Task.isCancelled, let self, self.isRunning else { return }
            self.shutDown()
            self.finish(error: "No answer within \(Self.timeout.components.seconds) seconds.")
        }
    }

    private func scheduleIdleShutdown() {
        idleTask?.cancel()
        guard server != nil else { return }
        idleTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: Self.idleLimit)
            guard !Task.isCancelled, let self, !self.isRunning else { return }
            self.shutDown()
        }
    }

    private func shutDown() {
        idleTask?.cancel()
        idleTask = nil
        let server = self.server
        self.server = nil
        threadID = nil
        queuedQuestion = nil
        server?.stop()
    }

    // MARK: Helpers

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

    private static var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
    }

    nonisolated static func prompt(question: String, history: [Message]) -> String {
        let earlier = history.suffix(historyLimit).filter { !$0.text.isEmpty }
        guard !earlier.isEmpty else { return question }
        var text = "Conversation so far:\n"
        for message in earlier {
            text += (message.role == .user ? "User: " : "Assistant: ") + message.text + "\n"
        }
        return text + "\nQuestion: \(question)"
    }

    private static func friendly(_ message: String) -> String {
        if message.localizedCaseInsensitiveContains("login") || message.localizedCaseInsensitiveContains("auth") {
            return "Codex is not signed in. Open the ChatGPT app's Codex once, or run codex login."
        }
        return String(message.prefix(200))
    }

    #if DEBUG
    /// Sample conversation for render checks.
    func previewLoad(_ exchange: [(question: String, answer: String)]) {
        messages = exchange.flatMap { [Message(role: .user, text: $0.question), Message(role: .assistant, text: $0.answer)] }
    }
    #endif
}

/// One `codex app-server` process, speaking JSON-RPC as one JSON object per line.
nonisolated final class CodexAppServer: @unchecked Sendable {
    private let process = Process()
    private let input = Pipe()
    private let output = Pipe()
    private var buffer = Data()
    /// Each line Codex prints, delivered on the main queue in order.
    @MainActor var onLine: ((Data) -> Void)?
    @MainActor var onExit: (() -> Void)?

    init(codex: URL, folder: URL) {
        process.executableURL = codex
        process.currentDirectoryURL = folder
        process.arguments = [
            "app-server",
            // A bare chat: none of your MCP servers, plugins, hooks or notifiers.
            "-c", "mcp_servers={}",
            "-c", "features.hooks=false",
            "-c", "features.plugins=false",
            "-c", "notify=[]",
            "-c", "model_reasoning_effort=low"
        ]
        process.standardInput = input
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
    }

    var isRunning: Bool { process.isRunning }

    func start() throws {
        // Only this handler touches the buffer, and it runs on one queue at a time.
        output.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard let self else { return }
            if data.isEmpty {
                handle.readabilityHandler = nil
                return
            }
            self.buffer.append(data)
            while let newline = self.buffer.firstIndex(of: 0x0A) {
                let line = Data(self.buffer[self.buffer.startIndex..<newline])
                self.buffer.removeSubrange(self.buffer.startIndex...newline)
                guard !line.isEmpty else { continue }
                DispatchQueue.main.async { [weak self] in
                    MainActor.assumeIsolated { self?.onLine?(line) }
                }
            }
        }
        process.terminationHandler = { [weak self] _ in
            DispatchQueue.main.async { [weak self] in
                MainActor.assumeIsolated { self?.onExit?() }
            }
        }
        try process.run()
    }

    func send(_ message: [String: Any]) {
        guard process.isRunning,
              var data = try? JSONSerialization.data(withJSONObject: message) else { return }
        data.append(0x0A)
        try? input.fileHandleForWriting.write(contentsOf: data)
    }

    func stop() {
        output.fileHandleForReading.readabilityHandler = nil
        try? input.fileHandleForWriting.close()
        if process.isRunning { process.terminate() }
    }
}
