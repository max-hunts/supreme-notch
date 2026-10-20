//
//  ChatGPTTranscriber.swift
//  BetterNotch
//
//  Turns a recording into text with ChatGPT's own transcription, the service the ChatGPT
//  app's dictation uses, on your ChatGPT subscription. It signs in with Codex's ChatGPT
//  login on this Mac (~/.codex/auth.json), the same login the Ask tab uses. The service is
//  not a public API, so it may change.
//

import Foundation

nonisolated enum ChatGPTTranscriber {
    enum Failure: LocalizedError {
        case notSignedIn
        case unauthorized
        case service(Int)
        case unreadable

        var errorDescription: String? {
            switch self {
            case .notSignedIn: return "Sign in to Codex with ChatGPT once (in the ChatGPT app) to use ChatGPT dictation."
            case .unauthorized: return "ChatGPT turned down the sign-in. Open Codex in the ChatGPT app, then try again."
            case let .service(status): return "ChatGPT couldn't transcribe that (error \(status))."
            case .unreadable: return "ChatGPT sent back something unexpected."
            }
        }
    }

    private static let endpoint = URL(string: "https://chatgpt.com/backend-api/transcribe")!

    /// The text of the recording. A rejected sign-in is refreshed through Codex once.
    static func transcribe(_ audio: Data, filename: String, contentType: String) async throws -> String {
        do {
            return try await post(audio, filename: filename, contentType: contentType, credentials: try credentials())
        } catch Failure.unauthorized {
            await CodexSignInRefresher.refresh()
            return try await post(audio, filename: filename, contentType: contentType, credentials: try credentials())
        }
    }

    private struct Credentials {
        let accessToken: String
        let accountID: String?
    }

    private static func credentials() throws -> Credentials {
        let home = ProcessInfo.processInfo.environment["CODEX_HOME"].map { URL(fileURLWithPath: $0) }
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".codex")
        guard let data = try? Data(contentsOf: home.appendingPathComponent("auth.json")),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let tokens = root["tokens"] as? [String: Any],
              let token = tokens["access_token"] as? String, !token.isEmpty else {
            throw Failure.notSignedIn
        }
        return Credentials(accessToken: token, accountID: tokens["account_id"] as? String)
    }

    private static func post(_ audio: Data, filename: String, contentType: String, credentials: Credentials) async throws -> String {
        let boundary = "----betternotch-transcribe-\(UUID().uuidString)"
        var body = Data()
        body.append(Data("--\(boundary)\r\nContent-Disposition: form-data; name=\"file\"; filename=\"\(filename)\"\r\nContent-Type: \(contentType)\r\n\r\n".utf8))
        body.append(audio)
        body.append(Data("\r\n--\(boundary)--\r\n".utf8))

        var request = URLRequest(url: endpoint, timeoutInterval: 45)
        request.httpMethod = "POST"
        request.setValue("Bearer \(credentials.accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("codex_cli_rs", forHTTPHeaderField: "originator")
        if let account = credentials.accountID {
            request.setValue(account, forHTTPHeaderField: "ChatGPT-Account-Id")
        }

        let (data, response) = try await URLSession.shared.upload(for: request, from: body)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        if status == 401 || status == 403 { throw Failure.unauthorized }
        guard (200..<300).contains(status) else { throw Failure.service(status) }
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let text = root["text"] as? String else {
            throw Failure.unreadable
        }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

/// Asks Codex to refresh its ChatGPT sign-in, which it saves back to auth.json. A short-lived
/// `codex app-server` does it, so this works whether or not the Ask tab is running one.
@MainActor
enum CodexSignInRefresher {
    static func refresh() async {
        guard let codex = AskAIModel.codexURL() else { return }
        let server = CodexAppServer(codex: codex, folder: AskAIModel.workingDirectory)
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            var finished = false
            func finish() {
                guard !finished else { return }
                finished = true
                server.stop()
                continuation.resume()
            }
            server.onLine = { line in
                guard let message = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
                      let id = message["id"] as? Int else { return }
                if id == 1 {
                    server.send(["method": "initialized"])
                    server.send(["id": 2, "method": "account/read", "params": ["refreshToken": true]])
                } else if id == 2 {
                    finish()
                }
            }
            server.onExit = { finish() }
            do {
                try server.start()
            } catch {
                finish()
                return
            }
            server.send(["id": 1, "method": "initialize", "params": [
                "clientInfo": ["name": "betternotch", "title": "BetterNotch", "version": AskAIModel.appVersion],
                "capabilities": NSNull()
            ]])
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(15))
                finish()
            }
        }
    }
}
