//
//  ClaudeDesktopSessionLocator.swift
//  SupremeNotch
//
//  Finds the Claude desktop app's own ID for a Claude Code session, so a click can open
//  that exact session with claude://code/continue?session=local_...
//
//  The app keeps one small JSON record per session under
//  ~/Library/Application Support/Claude/claude-code-sessions/<account>/<org>/local_<id>.json,
//  starting with {"sessionId":"local_...","cliSessionId":"<hook session_id>",...}.
//  Only the first few hundred bytes of each record are read: the two IDs, nothing else.
//  The format is undocumented, so every failure returns nil and callers fall back.
//

import AppKit
import Foundation

nonisolated enum ClaudeDesktopSessionLocator {
    /// How many of the most recently changed records to check before giving up.
    private static let maxRecordsScanned = 80
    private static let prefixBytes = 512

    private static var sessionsDirectoryURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Claude/claude-code-sessions", isDirectory: true)
    }

    /// The desktop app's "local_..." ID for a Claude Code session ID, if the session lives in the app.
    static func desktopSessionID(forCLISession cliSessionID: String) -> String? {
        guard isSafe(cliSessionID, pattern: "^[A-Za-z0-9-]{8,64}$") else { return nil }
        let needle = "\"cliSessionId\":\"\(cliSessionID)\""

        for url in recentRecordURLs() {
            guard let prefix = readPrefix(of: url), prefix.contains(needle) else { continue }
            let localID = url.deletingPathExtension().lastPathComponent
            // The record names itself; trust it only when it matches the file name.
            guard isSafe(localID, pattern: "^local_[A-Za-z0-9-]{1,64}$"),
                  prefix.contains("\"sessionId\":\"\(localID)\"") else { return nil }
            return localID
        }
        return nil
    }

    static func continueURL(forDesktopSession localID: String) -> URL? {
        guard isSafe(localID, pattern: "^local_[A-Za-z0-9-]{1,64}$") else { return nil }
        return URL(string: "claude://code/continue?session=\(localID)")
    }

    /// Opens the session in the Claude app. False when it is not a desktop app session.
    @MainActor
    static func open(cliSessionID: String) -> Bool {
        guard let localID = desktopSessionID(forCLISession: cliSessionID),
              let url = continueURL(forDesktopSession: localID) else { return false }
        return NSWorkspace.shared.open(url)
    }

    // MARK: - Private

    private static func recentRecordURLs() -> [URL] {
        let fileManager = FileManager.default
        let keys: [URLResourceKey] = [.contentModificationDateKey, .isDirectoryKey]
        var records: [(url: URL, modified: Date)] = []

        // <account>/<org>/local_*.json
        guard let accounts = try? fileManager.contentsOfDirectory(at: sessionsDirectoryURL, includingPropertiesForKeys: [.isDirectoryKey]) else {
            return []
        }
        for account in accounts {
            guard let orgs = try? fileManager.contentsOfDirectory(at: account, includingPropertiesForKeys: [.isDirectoryKey]) else { continue }
            for org in orgs {
                guard let files = try? fileManager.contentsOfDirectory(at: org, includingPropertiesForKeys: keys) else { continue }
                for file in files where file.lastPathComponent.hasPrefix("local_") && file.pathExtension == "json" {
                    let modified = (try? file.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                    records.append((file, modified))
                }
            }
        }

        return records
            .sorted { $0.modified > $1.modified }
            .prefix(maxRecordsScanned)
            .map(\.url)
    }

    private static func readPrefix(of url: URL) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        guard let data = try? handle.read(upToCount: prefixBytes) else { return nil }
        return String(decoding: data, as: UTF8.self)
    }

    private static func isSafe(_ value: String, pattern: String) -> Bool {
        value.range(of: pattern, options: .regularExpression) != nil
    }
}
