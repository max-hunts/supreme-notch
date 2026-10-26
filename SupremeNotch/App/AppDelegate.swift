//
//  AppDelegate.swift
//  SupremeNotch
//
//  Created by n0xbyte on 16.03.2026.
//

import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    // The rename migration must run before any manager reads its settings.
    private let environment: AppEnvironment = {
        let arguments = ProcessInfo.processInfo.arguments
        if !arguments.contains("-renderReadmeImages") && !arguments.contains("-layoutCheck") && !arguments.contains("-askAICheck") && !arguments.contains("-widthCheck") && !arguments.contains("-dictationCheck") {
            LegacyIdentityMigration.runIfNeeded()
        }
        return AppEnvironment()
    }()
    private var startupTask: Task<Void, Never>?
    private var didValidateSingleInstance = false

    private lazy var menuController = AppMenuController(
        settingsWindow: environment.settingsWindow,
        whatsNewWindow: environment.whatsNewWindow,
        agentEventManager: environment.agentEventManager
    )

    private lazy var lockScreenController = LockScreenStateController(
        model: environment.lockScreenOverlayModel,
        onLocked: { [environment] in
            environment.lockScreenWallpaperManager.screenDidLock()
        },
        onUnlocked: { [environment] in
            environment.lockScreenWallpaperManager.screenDidUnlock()
            environment.lockScreenWallpaperManager.refreshCachedDesktopWallpapers()
        }
    )

    private lazy var overlayController = SkyLightOverlayController(
        environment: environment
    )

    func applicationWillFinishLaunching(_ notification: Notification) {
        #if DEBUG
        if let directory = ReadmeImageRenderer.outputDirectory {
            ReadmeImageRenderer.render(environment: environment, to: directory)
            exit(0)
        }
        if let file = AskAICheck.outputFile {
            AskAICheck.run(to: file)
            return
        }
        if let check = DictationCheck.arguments {
            DictationCheck.run(audio: check.audio, report: check.report)
            return
        }
        #endif
        guard validateSingleRunningInstance() else { return }
        environment.lockScreenWallpaperManager.recoverSynchronously()
        environment.lockScreenWallpaperManager.refreshCachedDesktopWallpapers()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        #if DEBUG
        if AskAICheck.outputFile != nil || DictationCheck.arguments != nil { return }
        #endif
        guard validateSingleRunningInstance() else { return }

        #if !DEBUG
        // Debug builds share the settings, so only a release build may register itself.
        environment.settingsManager.repairLaunchAtLogin()
        #endif

        NSApp.setActivationPolicy(.accessory)

        menuController.install()
        environment.claudeHookIntegrationManager.migrateIfNeeded()
        environment.codexHookIntegrationManager.migrateIfNeeded()
        environment.cursorHookIntegrationManager.migrateIfNeeded()
        #if DEBUG
        // The layout check shows only its own sample alerts, never real ones.
        if LayoutCheck.outputDirectory == nil && WidthCheck.outputDirectory == nil { environment.agentEventManager.start() }
        #else
        environment.agentEventManager.start()
        #endif
        environment.musicManager.start()
        environment.networkStatusManager.start()
        overlayController.show()
        environment.lockScreenWallpaperManager.startDesktopWallpaperMonitoring()
        environment.lockScreenIdentityManager.start(
            observing: environment.lockScreenOverlayModel
        )

        startupTask?.cancel()
        startupTask = Task { @MainActor [weak self] in
            guard let self else { return }

            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled else { return }
            self.environment.focusManager.start()
            self.lockScreenController.start()

            try? await Task.sleep(for: .milliseconds(350))
            guard !Task.isCancelled else { return }
            self.environment.brightnessManager.start()
            self.environment.whatsNewWindow.showIfNeeded()

            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled else { return }
            self.environment.downloadGlanceManager.start()
            self.environment.airPodsGlanceManager.start()
            self.environment.calendarGlanceManager.start()
            self.environment.accessoryBatteryWarningManager.start()
            self.environment.externalDriveGlanceManager.start()
            self.environment.diskSpaceGlanceManager.start()
            self.environment.audioOutputManager.start()
            self.environment.micMuteManager.start()
            self.environment.systemStatsMonitor.start()
            self.environment.fileDragWatcher.start()
            if self.environment.settingsManager.showPortsPanel {
                self.environment.portsMonitor.startBackgroundRefresh()
            }
            self.startupTask = nil
        }

        #if DEBUG
        if let directory = LayoutCheck.outputDirectory {
            LayoutCheck.run(environment: environment, window: { [weak self] in
                self?.overlayController.debugIslandWindow
            }, to: directory)
        }
        if let directory = WidthCheck.outputDirectory {
            WidthCheck.run(environment: environment, window: { [weak self] in
                self?.overlayController.debugIslandWindow
            }, to: directory)
        }
        #endif
    }

    func applicationWillTerminate(_ notification: Notification) {
        startupTask?.cancel()
        startupTask = nil
        environment.musicManager.stop()
        environment.agentEventManager.stop()
        environment.downloadGlanceManager.stop()
        environment.calendarGlanceManager.stop()
        environment.airPodsGlanceManager.stop()
        environment.accessoryBatteryWarningManager.stop()
        environment.externalDriveGlanceManager.stop()
        environment.diskSpaceGlanceManager.stop()
        environment.audioOutputManager.stop()
        environment.extrasPanelModel.commitNote()
        environment.focusManager.stop()
        environment.brightnessManager.stop()
        environment.networkStatusManager.stop()
        environment.lockScreenWallpaperManager.stopDesktopWallpaperMonitoring()
        environment.lockScreenIdentityManager.stop()
        lockScreenController.stop()
        overlayController.stop()
        environment.lockScreenWallpaperManager.restoreSynchronously()
    }

    @discardableResult
    private func validateSingleRunningInstance() -> Bool {
        guard !didValidateSingleInstance else { return true }
        didValidateSingleInstance = true

        guard let bundleIdentifier = Bundle.main.bundleIdentifier else {
            return true
        }

        let currentProcessIdentifier = ProcessInfo.processInfo.processIdentifier
        let otherInstances = NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier)
            .filter { $0.processIdentifier != currentProcessIdentifier }

        guard let existingInstance = otherInstances.first else {
            return true
        }

        existingInstance.activate(options: [.activateAllWindows])
        NSApp.terminate(nil)
        return false
    }
}
