//
//  LegacyIdentityMigration.swift
//  SupremeNotch
//
//  One-time move from the app's earlier identities: BetterNotch (com.maxhunt.betternotch)
//  and, before that, Notchly (xyz.notchly.Notchly). Copies the newest one's settings, moves
//  its Application Support folder, copies the usage keys and turns Launch at Login back on.
//  Hook entries are rewritten by the hook managers afterwards.
//

import Foundation
import ServiceManagement

enum LegacyIdentityMigration {
    /// An earlier name of the app: its settings domain, Application Support folder and
    /// hook script prefix.
    struct Identity {
        let name: String
        let domain: String
        let hookPrefix: String
    }

    /// Newest first: settings come from the first one that has any.
    static let identities = [
        Identity(name: "BetterNotch", domain: "com.maxhunt.betternotch", hookPrefix: "betternotch"),
        Identity(name: "Notchly", domain: "xyz.notchly.Notchly", hookPrefix: "notchly")
    ]

    private static let doneKey = "migratedFromBetterNotch"
    private static let doneAtKey = "migratedFromBetterNotchAt"
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

        let copied = identities.contains { copySettings(from: $0, into: defaults) }
        moveSupportFolder()
        UsageCredentialStore.migrateLegacyKeys()
        if copied, defaults.bool(forKey: "launchAtLogin"), SMAppService.mainApp.status != .enabled {
            try? SMAppService.mainApp.register()
        }
    }

    /// Copies the old app's own keys; system and updater keys are left behind.
    private static func copySettings(from identity: Identity, into defaults: UserDefaults) -> Bool {
        let domain = identity.domain as CFString
        guard let keys = CFPreferencesCopyKeyList(domain, kCFPreferencesCurrentUser, kCFPreferencesAnyHost) as? [String],
              !keys.isEmpty,
              let values = CFPreferencesCopyMultiple(keys as CFArray, domain, kCFPreferencesCurrentUser, kCFPreferencesAnyHost) as? [String: Any]
        else { return false }

        let skippedPrefixes = ["NS", "Apple", "com.apple.", "SU", "WebKit", "migratedFrom"]
        for (key, value) in values where !skippedPrefixes.contains(where: key.hasPrefix) {
            if defaults.object(forKey: key) == nil {
                defaults.set(value, forKey: key)
            }
        }
        return true
    }

    /// Hook scripts, pending approvals, the lock screen wallpaper cache and logs, from the
    /// newest earlier folder. The old hook scripts are dropped; the hook managers install
    /// renamed ones, and a forwarding script stays at each old path for open sessions.
    private static func moveSupportFolder() {
        let fileManager = FileManager.default
        let support = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let current = support.appendingPathComponent("SupremeNotch", isDirectory: true)
        guard !fileManager.fileExists(atPath: current.path),
              let identity = identities.first(where: {
                  fileManager.fileExists(atPath: support.appendingPathComponent($0.name).path)
              })
        else { return }
        let legacy = support.appendingPathComponent(identity.name, isDirectory: true)
        try? fileManager.moveItem(at: legacy, to: current)
        let legacyBin = legacy.appendingPathComponent("bin", isDirectory: true)
        try? fileManager.createDirectory(at: legacyBin, withIntermediateDirectories: true)
        for source in ["claude", "codex", "cursor"] {
            let oldScript = current.appendingPathComponent("bin/\(identity.hookPrefix)-\(source)-hook")
            guard fileManager.fileExists(atPath: oldScript.path) else { continue }
            try? fileManager.removeItem(at: oldScript)
            let shim = legacyBin.appendingPathComponent("\(identity.hookPrefix)-\(source)-hook")
            let target = current.appendingPathComponent("bin/supremenotch-\(source)-hook").path
            let text = "#!/bin/sh\n# Forwards to SupremeNotch until open agent sessions restart.\n"
                + "[ -x \"\(target)\" ] && exec \"\(target)\" \"$@\"\nexit 0\n"
            try? text.write(to: shim, atomically: true, encoding: .utf8)
            try? fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: shim.path)
        }
    }

    /// Deletes each old folder once only the forwarding scripts are left and they expired.
    private static func removeExpiredShims(defaults: UserDefaults) {
        guard let doneAt = defaults.object(forKey: doneAtKey) as? Date,
              Date().timeIntervalSince(doneAt) > shimLifetime else { return }
        let fileManager = FileManager.default
        let support = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        for identity in identities {
            let legacy = support.appendingPathComponent(identity.name, isDirectory: true)
            guard fileManager.fileExists(atPath: legacy.path) else { continue }
            let contents = (try? fileManager.contentsOfDirectory(atPath: legacy.path)) ?? []
            let binContents = (try? fileManager.contentsOfDirectory(atPath: legacy.appendingPathComponent("bin").path)) ?? []
            guard contents.allSatisfy({ $0 == "bin" || $0 == ".DS_Store" }),
                  binContents.allSatisfy({ $0.hasPrefix("\(identity.hookPrefix)-") && $0.hasSuffix("-hook") }) else { continue }
            try? fileManager.removeItem(at: legacy)
        }
        defaults.removeObject(forKey: doneAtKey)
    }
}
