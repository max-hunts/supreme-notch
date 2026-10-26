//
//  CodexHookIntegrationManager.swift
//  SupremeNotch
//
//  Created by n0xbyte on 29.05.2026.
//
//  Codex reads hooks from ~/.codex/hooks.json (same shape as Claude Code's hooks object).
//  Earlier Notchly versions appended [[hooks.*]] tables to ~/.codex/config.toml; those
//  managed blocks are removed on install. Codex asks the user to trust new hooks via /hooks.
//

import Foundation
import Combine

@MainActor
final class CodexHookIntegrationManager: ObservableObject {
    @Published private(set) var installState: AgentHookInstallState = .unknown

    private let fileManager = FileManager.default

    var isInstalled: Bool {
        if case .installed = installState {
            return true
        }
        return false
    }

    var configPreview: String {
        let lines = handlers.map { handler in
            let timeout = handler.timeout.map { "  timeout \($0)s" } ?? ""
            return "\(handler.event): \(handler.command)\(timeout)"
        }
        return (["~/.codex/hooks.json"] + lines + ["", "After installing, run /hooks in Codex once and trust the SupremeNotch entries."])
            .joined(separator: "\n")
    }

    func refreshStatus() {
        installState = isHookInstalled() ? .installed : .notInstalled
    }

    func install() {
        installState = .installing

        do {
            try installHookScript()
            try removeLegacyConfigBlocks()
            try config.install(handlers: handlers, managedMarkers: managedMarkers)
            refreshStatus()
        } catch {
            installState = .failed(error.localizedDescription)
        }
    }

    func uninstall() {
        do {
            try config.uninstall(managedMarkers: managedMarkers)
            try removeLegacyConfigBlocks()
            try? fileManager.removeItem(at: hookScriptURL)
        } catch {
            installState = .failed(error.localizedDescription)
            return
        }
        refreshStatus()
    }

    /// Moves an earlier config.toml install to hooks.json and refreshes the script.
    /// Does nothing if SupremeNotch's Codex hooks were never installed.
    func migrateIfNeeded() {
        // Entries from before a rename point at the old folder: replace them.
        if AgentHookPaths.legacyHookScriptPaths(source: "codex").contains(where: config.mentions) {
            install()
            return
        }
        let legacy = (try? String(contentsOf: legacyConfigURL, encoding: .utf8))?.contains(hookScriptURL.path) ?? false
        guard legacy || config.mentions(hookScriptURL.path) else { return }
        guard legacy || !isHookInstalled() || scriptIsOutdated else { return }
        install()
    }

    /// This app's hook entries, including ones still pointing at an earlier name's script.
    private var managedMarkers: [String] {
        [hookScriptURL.path] + AgentHookPaths.legacyHookScriptPaths(source: "codex")
    }

    private var scriptIsOutdated: Bool {
        guard let current = try? String(contentsOf: hookScriptURL, encoding: .utf8) else { return true }
        return current != AgentHookScript.script(source: "codex", displayName: "Codex")
    }

    private func installHookScript() throws {
        try AgentHookPaths.ensureDirectories()
        try fileManager.createDirectory(at: AgentHookPaths.binDirectoryURL, withIntermediateDirectories: true)
        try AgentHookScript.script(source: "codex", displayName: "Codex")
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
            .init(event: "Stop", matcher: nil, command: command("completed"), timeout: nil),
            .init(event: "PreToolUse", matcher: nil, command: command("clear"), timeout: nil),
            .init(event: "PostToolUse", matcher: nil, command: command("clear"), timeout: nil),
            .init(event: "UserPromptSubmit", matcher: nil, command: command("clear"), timeout: nil)
        ]
    }

    private func command(_ event: String) -> String {
        "\"\(hookScriptURL.path)\" \(event)"
    }

    private var codexDirectoryURL: URL {
        fileManager.homeDirectoryForCurrentUser.appendingPathComponent(".codex", isDirectory: true)
    }

    private var config: AgentHookJSONConfig {
        AgentHookJSONConfig(fileURL: codexDirectoryURL.appendingPathComponent("hooks.json"))
    }

    private var legacyConfigURL: URL {
        codexDirectoryURL.appendingPathComponent("config.toml")
    }

    private var hookScriptURL: URL {
        AgentHookPaths.binDirectoryURL.appendingPathComponent("supremenotch-codex-hook")
    }

    // MARK: - Legacy config.toml cleanup

    /// Removes only [[hooks.*]] blocks whose command points at Notchly's script.
    /// A block ends at the next table header that is not part of the same hooks array,
    /// so unrelated arrays of tables such as [[skills.config]] are never swallowed.
    private func removeLegacyConfigBlocks() throws {
        guard fileManager.fileExists(atPath: legacyConfigURL.path) else { return }
        let original = try String(contentsOf: legacyConfigURL, encoding: .utf8)
        guard original.contains(hookScriptURL.path) else { return }

        let cleaned = Self.removingManagedBlocks(from: original, marker: hookScriptURL.path)
        guard cleaned != original else { return }

        let backupURL = legacyConfigURL.appendingPathExtension("supremenotch-backup")
        try? fileManager.removeItem(at: backupURL)
        try fileManager.copyItem(at: legacyConfigURL, to: backupURL)
        try cleaned.write(to: legacyConfigURL, atomically: true, encoding: .utf8)
    }

    nonisolated static func removingManagedBlocks(from config: String, marker: String) -> String {
        var kept: [String] = []
        var block: [String] = []
        var inHookBlock = false

        func flush() {
            if !block.joined(separator: "\n").contains(marker) {
                kept.append(contentsOf: block)
            }
            block.removeAll()
        }

        for line in config.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if trimmed == "# Notchly Codex alerts" {
                continue
            }

            if trimmed.hasPrefix("[[hooks.") {
                // [[hooks.Event]] starts a block; [[hooks.Event.hooks]] continues it.
                let continuesBlock = inHookBlock && trimmed.hasSuffix(".hooks]]")
                if !continuesBlock {
                    flush()
                }
                inHookBlock = true
                block.append(line)
                continue
            }

            if inHookBlock && trimmed.hasPrefix("[") {
                flush()
                inHookBlock = false
                kept.append(line)
                continue
            }

            if inHookBlock {
                block.append(line)
            } else {
                kept.append(line)
            }
        }

        flush()

        var result = kept.joined(separator: "\n")
        while result.contains("\n\n\n") {
            result = result.replacingOccurrences(of: "\n\n\n", with: "\n\n")
        }
        return result
    }
}
