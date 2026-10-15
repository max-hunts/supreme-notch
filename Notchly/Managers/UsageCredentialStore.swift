//
//  UsageCredentialStore.swift
//  Notchly
//
//  Claude and Codex usage credentials kept in the macOS Keychain, so the Usage tab works
//  without claude-usage-monitor's own config file. They are handed to that tool only
//  through environment variables for the one run, which its README documents as
//  overriding its saved config field by field. Empty fields fall back to its config.
//

import Foundation
import Security

nonisolated enum UsageCredentialField: String, CaseIterable, Identifiable {
    case claudeOrgID = "CLAUDE_ORG_ID"
    case claudeSessionKey = "CLAUDE_SESSION_KEY"
    case claudeCFClearance = "CLAUDE_CF_CLEARANCE"
    case claudeCFBM = "CLAUDE_CF_BM"
    case codexAccessToken = "CODEX_ACCESS_TOKEN"
    case codexAccountID = "CODEX_ACCOUNT_ID"
    case codexCookie = "CODEX_COOKIE"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .claudeOrgID: return "Org ID"
        case .claudeSessionKey: return "sessionKey cookie"
        case .claudeCFClearance: return "cf_clearance cookie"
        case .claudeCFBM: return "__cf_bm cookie (optional)"
        case .codexAccessToken: return "Authorization (Bearer …)"
        case .codexAccountID: return "chatgpt-account-id"
        case .codexCookie: return "Cookie header (optional)"
        }
    }

    /// IDs are shown; tokens and cookies are masked.
    var isSecret: Bool {
        switch self {
        case .claudeOrgID, .codexAccountID: return false
        default: return true
        }
    }

    var isClaude: Bool { rawValue.hasPrefix("CLAUDE") }
}

nonisolated enum UsageCredentialStore {
    private static let service = "BetterNotch AI Usage"

    static func value(_ field: UsageCredentialField) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: field.rawValue,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data,
              let text = String(data: data, encoding: .utf8), !text.isEmpty else { return nil }
        return text
    }

    /// Saves a value, or deletes it when empty.
    static func set(_ value: String, for field: UsageCredentialField) {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        let base: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: field.rawValue
        ]
        SecItemDelete(base as CFDictionary)
        guard !trimmed.isEmpty else { return }
        var item = base
        item[kSecValueData as String] = Data(trimmed.utf8)
        // Readable only on this Mac while it is unlocked; never synced to iCloud.
        item[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        SecItemAdd(item as CFDictionary, nil)
    }

    /// Copies keys saved before the app was renamed from Notchly. macOS may ask once per
    /// key, because the old app owns those Keychain items. The old items are left alone.
    static func migrateLegacyKeys() {
        for field in UsageCredentialField.allCases where value(field) == nil {
            let query: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: "Notchly AI Usage",
                kSecAttrAccount as String: field.rawValue,
                kSecReturnData as String: true,
                kSecMatchLimit as String: kSecMatchLimitOne
            ]
            var result: AnyObject?
            guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
                  let data = result as? Data,
                  let text = String(data: data, encoding: .utf8), !text.isEmpty else { continue }
            set(text, for: field)
        }
    }

    static func hasValue(_ field: UsageCredentialField) -> Bool {
        value(field) != nil
    }

    /// Environment for one run of claude-usage-monitor: only fields saved in Notchly.
    static func environmentOverrides() -> [String: String] {
        var environment: [String: String] = [:]
        for field in UsageCredentialField.allCases {
            if let value = value(field) {
                environment[field.rawValue] = value
            }
        }
        return environment
    }
}
