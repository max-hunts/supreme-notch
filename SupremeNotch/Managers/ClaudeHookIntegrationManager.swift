//
//  ClaudeHookIntegrationManager.swift
//  SupremeNotch
//
//  Created by n0xbyte on 25.03.2026.
//

import Foundation
import Combine

@MainActor
final class ClaudeHookIntegrationManager: ObservableObject {
    @Published private(set) var installState: AgentHookInstallState = .unknown

    private let fileManager = FileManager.default

    var isInstalled: Bool {
        if case .installed = installState {
            return true
        }
        return false
    }

    var configPreview: String {
        handlers
            .map { handler in
                let matcher = handler.matcher.map { " [\($0)]" } ?? ""
                let timeout = handler.timeout.map { "  timeout \($0)s" } ?? ""
                return "\(handler.event)\(matcher): \(handler.command)\(timeout)"
            }
            .joined(separator: "\n")
    }

    func refreshStatus() {
        installState = isHookInstalled() ? .installed : .notInstalled
    }

    func install() {
        installState = .installing

        do {
            try installHookScript()
            try config.install(handlers: handlers, managedMarkers: managedMarkers)
            refreshStatus()
        } catch {
            installState = .failed(error.localizedDescription)
        }
    }

    func uninstall() {
        do {
            try config.uninstall(managedMarkers: managedMarkers)
            try? fileManager.removeItem(at: hookScriptURL)
        } catch {
            installState = .failed(error.localizedDescription)
            return
        }
        refreshStatus()
    }

    /// Brings an earlier install up to date at launch: new script and the new
    /// handler set (separate notify command, permission timeout). Only SupremeNotch's own
    /// entries change; settings.json is backed up first. Does nothing if never installed.
    func migrateIfNeeded() {
        // Entries from before a rename point at the old folder: replace them.
        if AgentHookPaths.legacyHookScriptPaths(source: "claude").contains(where: config.mentions) {
            install()
            return
        }
        guard config.mentions(hookScriptURL.path), !isHookInstalled() || scriptIsOutdated else { return }
        install()
    }

    /// This app's hook entries, including ones still pointing at an earlier name's script.
    private var managedMarkers: [String] {
        [hookScriptURL.path] + AgentHookPaths.legacyHookScriptPaths(source: "claude")
    }

    private var scriptIsOutdated: Bool {
        guard let current = try? String(contentsOf: hookScriptURL, encoding: .utf8) else { return true }
        return current != AgentHookScript.script(source: "claude", displayName: "Claude Code")
    }

    private func installHookScript() throws {
        try AgentHookPaths.ensureDirectories()
        try fileManager.createDirectory(at: AgentHookPaths.binDirectoryURL, withIntermediateDirectories: true)
        try AgentHookScript.script(source: "claude", displayName: "Claude Code")
            .write(to: hookScriptURL, atomically: true, encoding: .utf8)
        try fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: hookScriptURL.path)
    }

    private func isHookInstalled() -> Bool {
        guard fileManager.isExecutableFile(atPath: hookScriptURL.path) else { return false }
        return handlers.allSatisfy(config.contains)
    }

    private var handlers: [AgentHookJSONConfig.Handler] {
        [
            .init(event: "PermissionRequest", matcher: nil, command: command("approval"),
                  timeout: AgentHookPaths.permissionHookTimeoutSeconds),
            .init(event: "Notification", matcher: "permission_prompt", command: command("notify"), timeout: nil),
            .init(event: "Notification", matcher: "idle_prompt", command: command("waiting"), timeout: nil),
            .init(event: "Stop", matcher: nil, command: command("completed"), timeout: nil),
            .init(event: "StopFailure", matcher: nil, command: command("failed"), timeout: nil),
            .init(event: "PreToolUse", matcher: nil, command: command("clear"), timeout: nil),
            .init(event: "PostToolUse", matcher: nil, command: command("clear"), timeout: nil),
            .init(event: "PermissionDenied", matcher: nil, command: command("clear"), timeout: nil),
            .init(event: "UserPromptSubmit", matcher: nil, command: command("clear"), timeout: nil),
            .init(event: "SessionEnd", matcher: nil, command: command("clear"), timeout: nil)
        ]
    }

    private func command(_ event: String) -> String {
        "\"\(hookScriptURL.path)\" \(event)"
    }

    private var config: AgentHookJSONConfig {
        AgentHookJSONConfig(
            fileURL: fileManager.homeDirectoryForCurrentUser
                .appendingPathComponent(".claude", isDirectory: true)
                .appendingPathComponent("settings.json")
        )
    }

    private var hookScriptURL: URL {
        AgentHookPaths.binDirectoryURL.appendingPathComponent("supremenotch-claude-hook")
    }
}
