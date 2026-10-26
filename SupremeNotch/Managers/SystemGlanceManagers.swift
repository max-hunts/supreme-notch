//
//  SystemGlanceManagers.swift
//  SupremeNotch
//
//  Low accessory battery, external drives with eject, and low disk space.
//

import AppKit
import Combine
import DiskArbitration
import Foundation
import IOKit.ps

// MARK: - Low accessory battery

@MainActor
final class AccessoryBatteryWarningManager {
    private let settingsManager: SettingsManager
    private let agentEventManager: AgentEventManager
    private var cancellables = Set<AnyCancellable>()
    private var pollTask: Task<Void, Never>?
    private var runLoopSource: CFRunLoopSource?
    /// Parts already warned about, keyed by power source and part.
    private var warned = Set<String>()

    init(settingsManager: SettingsManager, agentEventManager: AgentEventManager) {
        self.settingsManager = settingsManager
        self.agentEventManager = agentEventManager
    }

    func start() {
        settingsManager.$showAccessoryBatteryWarning
            .removeDuplicates()
            .sink { [weak self] enabled in
                enabled ? self?.enable() : self?.disable()
            }
            .store(in: &cancellables)
    }

    func stop() {
        cancellables.removeAll()
        disable()
    }

    private func enable() {
        guard pollTask == nil else { return }

        // Power source changes wake us immediately; the poll is a safety net.
        let context = Unmanaged.passUnretained(self).toOpaque()
        if let source = IOPSNotificationCreateRunLoopSource({ context in
            guard let context else { return }
            let manager = Unmanaged<AccessoryBatteryWarningManager>.fromOpaque(context).takeUnretainedValue()
            DispatchQueue.main.async {
                MainActor.assumeIsolated { manager.check() }
            }
        }, context)?.takeRetainedValue() {
            CFRunLoopAddSource(CFRunLoopGetMain(), source, .defaultMode)
            runLoopSource = source
        }

        pollTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(20))
            while !Task.isCancelled {
                self?.check()
                try? await Task.sleep(for: .seconds(120))
            }
        }
    }

    private func disable() {
        pollTask?.cancel()
        pollTask = nil
        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .defaultMode)
        }
        runLoopSource = nil
    }

    private func check() {
        guard settingsManager.showAccessoryBatteryWarning else { return }

        for source in AccessoryBatteryReader.allAccessorySources() {
            let name = source["Name"] as? String ?? "Accessory"
            let sourceID = source["Power Source ID"] as? Int ?? name.hashValue
            let threshold = source["Low Warn Level"] as? Int ?? 20
            let category = source["Accessory Category"] as? String ?? ""

            let subsources: [[String: Any]]
            if let combined = source["Combined Parts"] as? [[String: Any]], !combined.isEmpty {
                subsources = combined
            } else {
                subsources = [source]
            }

            for sub in subsources {
                guard let level = sub["Current Capacity"] as? Int else { continue }
                let charging = (sub["Is Charging"] as? Bool) ?? ((sub["Is Charging"] as? Int) == 1)
                let partID = sub["Part Identifier"] as? String ?? "Single"
                let key = "\(sourceID)|\(partID)"

                if charging || level > threshold + 5 {
                    warned.remove(key)
                    continue
                }
                guard level <= threshold, !warned.contains(key) else { continue }
                warned.insert(key)

                let kind: GlanceBatteryPart.Kind
                switch partID {
                case "Left": kind = .left
                case "Right": kind = .right
                case "Case": kind = .case
                default: kind = .single
                }

                let deviceName = name.replacingOccurrences(of: " Case", with: "")
                agentEventManager.publishGlance(
                    source: "battery-warning",
                    title: "Low battery",
                    detail: deviceName,
                    style: AgentGlanceStyle(
                        symbolName: Self.symbol(forName: deviceName, category: category),
                        red: 1.0, green: 0.36, blue: 0.32
                    ),
                    actionURL: URL(string: "x-apple.systempreferences:com.apple.BluetoothSettings"),
                    ttl: 6,
                    batteryParts: [GlanceBatteryPart(kind: kind, level: level, isCharging: false)]
                )
                return
            }
        }
    }

    nonisolated static func symbol(forName name: String, category: String) -> String {
        switch category.lowercased() {
        case "mouse":
            return "magicmouse.fill"
        case "keyboard":
            return "keyboard.fill"
        case "trackpad":
            return "rectangle.and.hand.point.up.left.fill"
        case "pencil", "stylus":
            return "applepencil"
        default:
            return AirPodsGlanceManager.deviceSymbol(for: name)
        }
    }
}

// MARK: - External drives

@MainActor
final class ExternalDriveGlanceManager {
    private let settingsManager: SettingsManager
    private let agentEventManager: AgentEventManager
    private var cancellables = Set<AnyCancellable>()
    private var observers: [NSObjectProtocol] = []
    /// Volume paths currently mounted that qualify as external drives.
    private var trackedVolumes = Set<String>()

    init(settingsManager: SettingsManager, agentEventManager: AgentEventManager) {
        self.settingsManager = settingsManager
        self.agentEventManager = agentEventManager
    }

    func start() {
        settingsManager.$showDriveGlance
            .removeDuplicates()
            .sink { [weak self] enabled in
                enabled ? self?.enable() : self?.disable()
            }
            .store(in: &cancellables)
    }

    func stop() {
        cancellables.removeAll()
        disable()
    }

    private func enable() {
        guard observers.isEmpty else { return }

        let keys: [URLResourceKey] = [.volumeIsLocalKey]
        for url in FileManager.default.mountedVolumeURLs(includingResourceValuesForKeys: keys, options: [.skipHiddenVolumes]) ?? []
            where VolumeEjector.isExternalDrive(url) {
            trackedVolumes.insert(url.path)
        }

        let center = NSWorkspace.shared.notificationCenter
        observers.append(center.addObserver(forName: NSWorkspace.didMountNotification, object: nil, queue: .main) { [weak self] note in
            let url = note.userInfo?[NSWorkspace.volumeURLUserInfoKey] as? URL
            MainActor.assumeIsolated { self?.mounted(url) }
        })
        observers.append(center.addObserver(forName: NSWorkspace.didUnmountNotification, object: nil, queue: .main) { [weak self] note in
            let url = note.userInfo?[NSWorkspace.volumeURLUserInfoKey] as? URL
            MainActor.assumeIsolated { self?.unmounted(url) }
        })
    }

    private func disable() {
        let center = NSWorkspace.shared.notificationCenter
        observers.forEach(center.removeObserver)
        observers.removeAll()
        trackedVolumes.removeAll()
    }

    private func mounted(_ url: URL?) {
        guard let url, VolumeEjector.isExternalDrive(url) else { return }
        trackedVolumes.insert(url.path)

        let values = try? url.resourceValues(forKeys: [.volumeAvailableCapacityKey, .volumeLocalizedNameKey])
        let name = values?.volumeLocalizedName ?? url.lastPathComponent
        let free = values?.volumeAvailableCapacity.map {
            ByteCountFormatter.string(fromByteCount: Int64($0), countStyle: .file) + " free"
        }

        agentEventManager.publishGlance(
            source: "drive",
            title: free.map { "Drive connected · \($0) · click to eject" } ?? "Drive connected · click to eject",
            detail: name,
            style: AgentGlanceStyle(symbolName: "externaldrive.fill", red: 0.75, green: 0.78, blue: 0.85),
            actionURL: nil,
            ttl: 6,
            action: .ejectVolume(url)
        )
    }

    private func unmounted(_ url: URL?) {
        guard let url, trackedVolumes.remove(url.path) != nil else { return }
        VolumeEjector.announceSafeToRemove(name: url.lastPathComponent, agentEventManager: agentEventManager)
    }
}

/// Ejects external drives and reports the result in the notch.
@MainActor
enum VolumeEjector {
    static func eject(_ url: URL, agentEventManager: AgentEventManager) {
        let name = url.lastPathComponent
        agentEventManager.dismissGlance(source: "drive")

        Task.detached(priority: .userInitiated) {
            do {
                try NSWorkspace.shared.unmountAndEjectDevice(at: url)
                // didUnmountNotification announces "safe to remove".
            } catch {
                await MainActor.run {
                    agentEventManager.publishGlance(
                        source: "drive",
                        title: "Can't eject · an app is using it",
                        detail: name,
                        style: AgentGlanceStyle(symbolName: "exclamationmark.triangle.fill", red: 1.0, green: 0.75, blue: 0.3),
                        actionURL: nil,
                        ttl: 5
                    )
                }
            }
        }
    }

    static func announceSafeToRemove(name: String, agentEventManager: AgentEventManager) {
        agentEventManager.publishGlance(
            source: "drive",
            title: "Safe to remove",
            detail: name,
            style: AgentGlanceStyle(symbolName: "checkmark.circle.fill", red: 0.2, green: 0.84, blue: 0.29),
            actionURL: nil,
            ttl: 4
        )
    }

    /// True for physical, ejectable, non-network drives. Disk images and the internal disk are excluded.
    nonisolated static func isExternalDrive(_ url: URL) -> Bool {
        guard let session = DASessionCreate(kCFAllocatorDefault),
              let disk = DADiskCreateFromVolumePath(kCFAllocatorDefault, session, url as CFURL),
              let description = DADiskCopyDescription(disk) as? [String: Any] else {
            return false
        }

        if description[kDADiskDescriptionVolumeNetworkKey as String] as? Bool == true { return false }
        if description[kDADiskDescriptionDeviceInternalKey as String] as? Bool == true { return false }

        let model = (description[kDADiskDescriptionDeviceModelKey as String] as? String ?? "").lowercased()
        let protocolName = (description[kDADiskDescriptionDeviceProtocolKey as String] as? String ?? "").lowercased()
        if model.contains("disk image") || protocolName.contains("disk image") || protocolName.contains("virtual") {
            return false
        }

        let ejectable = description[kDADiskDescriptionMediaEjectableKey as String] as? Bool ?? false
        let removable = description[kDADiskDescriptionMediaRemovableKey as String] as? Bool ?? false
        let external = description[kDADiskDescriptionDeviceInternalKey as String] as? Bool == false
        return ejectable || removable || external
    }
}

// MARK: - Low disk space

@MainActor
final class DiskSpaceGlanceManager {
    private let settingsManager: SettingsManager
    private let agentEventManager: AgentEventManager
    private var cancellables = Set<AnyCancellable>()
    private var pollTask: Task<Void, Never>?
    private var hasWarned = false

    static let warnFraction = 0.10
    static let rearmFraction = 0.15

    init(settingsManager: SettingsManager, agentEventManager: AgentEventManager) {
        self.settingsManager = settingsManager
        self.agentEventManager = agentEventManager
    }

    func start() {
        settingsManager.$showLowDiskWarning
            .removeDuplicates()
            .sink { [weak self] enabled in
                enabled ? self?.enable() : self?.disable()
            }
            .store(in: &cancellables)
    }

    func stop() {
        cancellables.removeAll()
        disable()
    }

    private func enable() {
        guard pollTask == nil else { return }
        pollTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(45))
            while !Task.isCancelled {
                self?.check()
                try? await Task.sleep(for: .seconds(600))
            }
        }
    }

    private func disable() {
        pollTask?.cancel()
        pollTask = nil
    }

    private func check() {
        guard let status = Self.startupDiskStatus() else { return }

        if status.fraction >= Self.rearmFraction {
            hasWarned = false
            return
        }
        guard status.fraction < Self.warnFraction, !hasWarned else { return }
        hasWarned = true

        let free = ByteCountFormatter.string(fromByteCount: status.available, countStyle: .file)
        let total = ByteCountFormatter.string(fromByteCount: status.total, countStyle: .file)
        agentEventManager.publishGlance(
            source: "disk",
            title: "Low disk space · click for Storage",
            detail: "\(free) free of \(total)",
            style: AgentGlanceStyle(symbolName: "internaldrive.fill", red: 1.0, green: 0.62, blue: 0.25),
            actionURL: URL(string: "x-apple.systempreferences:com.apple.settings.Storage"),
            ttl: 8
        )
    }

    nonisolated static func startupDiskStatus() -> (available: Int64, total: Int64, fraction: Double)? {
        let url = URL(fileURLWithPath: "/")
        guard let values = try? url.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey, .volumeTotalCapacityKey]),
              let available = values.volumeAvailableCapacityForImportantUsage,
              let total = values.volumeTotalCapacity, total > 0 else {
            return nil
        }
        return (available, Int64(total), Double(available) / Double(total))
    }
}
