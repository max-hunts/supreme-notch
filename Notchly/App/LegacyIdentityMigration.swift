//
//  LegacyIdentityMigration.swift
//  BetterNotch
//
//  One-time move from the app's earlier identity (Notchly, xyz.notchly.Notchly): copies
//  its settings, moves its Application Support folder, copies the usage keys and turns
//  Launch at Login back on. Hook entries are rewritten by the hook managers afterwards.
//

import Foundation
import ServiceManagement

enum LegacyIdentityMigration {
    private static let doneKey = "migratedFromNotchly"
    private static let legacyDomain = "xyz.notchly.Notchly" as CFString

    private static let doneAtKey = "migratedFromNotchlyAt"
    /// Agent sessions that were already open keep calling the old hook paths until they
    /// restart, so forwarding scripts stay there this long.
    private static let shimLifetime: TimeInterval = 3 * 24 * 60 * 60

    static func runIfNeeded() {
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: doneKey) else {
            removeExpiredShims(defaults: defaults)
            return
        }
        defaults.set(true, forKey: doneKey)
        defaults.set(Date(), forKey: doneAtKey)

        let copied = copySettings(into: defaults)
        moveSupportFolder()
        UsageCredentialStore.migrateLegacyKeys()
        if copied, defaults.bool(forKey: "launchAtLogin"), SMAppService.mainApp.status != .enabled {
            try? SMAppService.mainApp.register()
        }
    }

    /// Copies the old app's own keys; system and updater keys are left behind.
    private static func copySettings(into defaults: UserDefaults) -> Bool {
        guard let keys = CFPreferencesCopyKeyList(legacyDomain, kCFPreferencesCurrentUser, kCFPreferencesAnyHost) as? [String],
              !keys.isEmpty,
              let values = CFPreferencesCopyMultiple(keys as CFArray, legacyDomain, kCFPreferencesCurrentUser, kCFPreferencesAnyHost) as? [String: Any]
        else { return false }

        let skippedPrefixes = ["NS", "Apple", "com.apple.", "SU", "WebKit"]
        for (key, value) in values where !skippedPrefixes.contains(where: key.hasPrefix) {
            if defaults.object(forKey: key) == nil {
                defaults.set(value, forKey: key)
            }
        }
        return true
    }

    /// Hook scripts, pending approvals, the lock screen wallpaper cache and logs. The old
    /// hook scripts are dropped; the hook managers install renamed ones.
    private static func moveSupportFolder() {
        let fileManager = FileManager.default
        let support = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let legacy = support.appendingPathComponent("Notchly", isDirectory: true)
        let current = support.appendingPathComponent("BetterNotch", isDirectory: true)
        guard fileManager.fileExists(atPath: legacy.path), !fileManager.fileExists(atPath: current.path) else { return }
        try? fileManager.moveItem(at: legacy, to: current)
        let legacyBin = legacy.appendingPathComponent("bin", isDirectory: true)
        try? fileManager.createDirectory(at: legacyBin, withIntermediateDirectories: true)
        for source in ["claude", "codex", "cursor"] {
            let oldScript = current.appendingPathComponent("bin/notchly-\(source)-hook")
            guard fileManager.fileExists(atPath: oldScript.path) else { continue }
            try? fileManager.removeItem(at: oldScript)
            let shim = legacyBin.appendingPathComponent("notchly-\(source)-hook")
            let target = current.appendingPathComponent("bin/betternotch-\(source)-hook").path
            let text = "#!/bin/sh\n# Forwards to BetterNotch until open agent sessions restart.\n"
                + "[ -x \"\(target)\" ] && exec \"\(target)\" \"$@\"\nexit 0\n"
            try? text.write(to: shim, atomically: true, encoding: .utf8)
            try? fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: shim.path)
        }
    }

    /// Deletes the old folder once only the forwarding scripts are left and they expired.
    private static func removeExpiredShims(defaults: UserDefaults) {
        guard let doneAt = defaults.object(forKey: doneAtKey) as? Date,
              Date().timeIntervalSince(doneAt) > shimLifetime else { return }
        let fileManager = FileManager.default
        let legacy = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Notchly", isDirectory: true)
        let contents = (try? fileManager.contentsOfDirectory(atPath: legacy.path)) ?? []
        let binContents = (try? fileManager.contentsOfDirectory(atPath: legacy.appendingPathComponent("bin").path)) ?? []
        guard contents.allSatisfy({ $0 == "bin" || $0 == ".DS_Store" }),
              binContents.allSatisfy({ $0.hasPrefix("notchly-") && $0.hasSuffix("-hook") }) else { return }
        try? fileManager.removeItem(at: legacy)
        defaults.removeObject(forKey: doneAtKey)
    }
}
