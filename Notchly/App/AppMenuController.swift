//
//  AppMenuController.swift
//  Notchly
//
//  Created by n0xbyte on 03.05.2026.
//

import AppKit
import Sparkle

@MainActor
final class AppMenuController: NSObject {
    private var statusItem: NSStatusItem?
    private var hasStartedUpdater = false

    private let settingsWindow: SettingsWindow
    private let whatsNewWindow: WhatsNewWindow
    private let updaterController: SPUStandardUpdaterController
    private let agentEventManager: AgentEventManager

    init(
        settingsWindow: SettingsWindow,
        whatsNewWindow: WhatsNewWindow,
        updaterController: SPUStandardUpdaterController,
        agentEventManager: AgentEventManager
    ) {
        self.settingsWindow = settingsWindow
        self.whatsNewWindow = whatsNewWindow
        self.updaterController = updaterController
        self.agentEventManager = agentEventManager
        super.init()
    }

    func install() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem = item

        if let button = item.button {
            let image = NSImage(named: "MenuBarIcon")
            image?.isTemplate = true
            button.image = image
        }

        item.menu = makeMenu()
        // The updater is never started: its feed is the upstream project's, and an update
        // from there would replace this build. Re-enable once it points at our own feed.
    }

    private func makeMenu() -> NSMenu {
        let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "Unknown"

        let versionItem = NSMenuItem(
            title: "Version \(appVersion)",
            action: nil,
            keyEquivalent: ""
        )
        versionItem.isEnabled = false

        let settingsItem = NSMenuItem(
            title: "Settings",
            action: #selector(openSettings),
            keyEquivalent: ","
        )
        settingsItem.target = self

        let whatsNewItem = NSMenuItem(
            title: "What's New...",
            action: #selector(openWhatsNew),
            keyEquivalent: ""
        )
        whatsNewItem.target = self

        let quitItem = NSMenuItem(
            title: "Quit",
            action: #selector(quitApp),
            keyEquivalent: "q"
        )
        quitItem.target = self

        let portsItem = NSMenuItem(title: "Listening Ports", action: nil, keyEquivalent: "")
        let portsMenu = NSMenu(title: "Listening Ports")
        portsMenu.delegate = self
        portsItem.submenu = portsMenu

        let menu = NSMenu()
        menu.addItem(versionItem)
        menu.addItem(settingsItem)
        menu.addItem(portsItem)

#if DEBUG
        let testCodexItem = NSMenuItem(
            title: "Test Codex Alert",
            action: #selector(testCodexAlert),
            keyEquivalent: ""
        )
        testCodexItem.target = self
        menu.addItem(testCodexItem)

        let testClaudeItem = NSMenuItem(
            title: "Test Claude Code Alert",
            action: #selector(testClaudeAlert),
            keyEquivalent: ""
        )
        testClaudeItem.target = self
        menu.addItem(testClaudeItem)

        let testCursorItem = NSMenuItem(
            title: "Test Cursor Alert",
            action: #selector(testCursorAlert),
            keyEquivalent: ""
        )
        testCursorItem.target = self
        menu.addItem(testCursorItem)

        let testWhatsNewItem = NSMenuItem(
            title: "Test What's New Update",
            action: #selector(testWhatsNewUpdate),
            keyEquivalent: ""
        )
        testWhatsNewItem.target = self
        menu.addItem(testWhatsNewItem)
#endif

        menu.addItem(.separator())
        menu.addItem(whatsNewItem)
        menu.addItem(quitItem)
        return menu
    }

#if DEBUG
    @objc private func testCodexAlert() {
        agentEventManager.publish(
            source: "codex",
            kind: .accessRequest,
            title: "Need approval",
            message: "Test alert from menu",
            ttl: 3.0
        )
    }

    @objc private func testClaudeAlert() {
        agentEventManager.publish(
            source: "claude",
            kind: .accessRequest,
            title: "Need approval",
            message: "Test Claude Code alert from menu",
            ttl: 3.0
        )
    }

    @objc private func testCursorAlert() {
        agentEventManager.publish(
            source: "cursor",
            kind: .accessRequest,
            title: "Need approval",
            message: "Test Cursor alert from menu",
            ttl: 3.0
        )
    }

    @objc private func testWhatsNewUpdate() {
        whatsNewWindow.simulateUpdateForTesting()
    }
#endif

    @objc private func openSettings() {
        settingsWindow.show()
    }

    @objc private func openWhatsNew() {
        whatsNewWindow.show()
    }

    /// Disabled in this self-built version: the upstream feed would replace it with the
    /// upstream release. The menu item is hidden; this stays a no-op until the updater is
    /// pointed at our own feed.
    @objc private func checkForUpdates() {}

    @objc private func quitApp() {
        NSApp.terminate(nil)
    }

    private func startUpdaterIfNeeded() {
        guard !hasStartedUpdater else { return }
        updaterController.startUpdater()
        hasStartedUpdater = true
    }
}


// MARK: - Listening ports submenu

extension AppMenuController: NSMenuDelegate {
    func menuNeedsUpdate(_ menu: NSMenu) {
        guard menu.title == "Listening Ports" else { return }
        menu.removeAllItems()

        let ports = ListeningPortsMonitor.snapshot()
        guard !ports.isEmpty else {
            let empty = NSMenuItem(title: "No dev servers listening", action: nil, keyEquivalent: "")
            empty.isEnabled = false
            menu.addItem(empty)
            return
        }

        for port in ports {
            let item = NSMenuItem(title: "\(port.port)   \(port.label)", action: nil, keyEquivalent: "")
            let actions = NSMenu()

            let open = NSMenuItem(title: "Open http://localhost:\(port.port)", action: #selector(openPort(_:)), keyEquivalent: "")
            open.target = self
            open.representedObject = port.port
            actions.addItem(open)
            actions.addItem(.separator())

            if let container = port.dockerContainer {
                let stop = NSMenuItem(title: "Stop Container \(container)", action: #selector(stopContainer(_:)), keyEquivalent: "")
                stop.target = self
                stop.representedObject = container
                actions.addItem(stop)
            } else if port.canStop {
                let stop = NSMenuItem(title: "Stop \(port.command) (PID \(port.pid))", action: #selector(stopPort(_:)), keyEquivalent: "")
                stop.target = self
                stop.representedObject = Int(port.pid)
                actions.addItem(stop)

                let force = NSMenuItem(title: "Force Stop", action: #selector(forceStopPort(_:)), keyEquivalent: "")
                force.target = self
                force.representedObject = Int(port.pid)
                actions.addItem(force)
            } else {
                let note = NSMenuItem(title: "Managed by Docker", action: nil, keyEquivalent: "")
                note.isEnabled = false
                actions.addItem(note)
            }

            item.submenu = actions
            menu.addItem(item)
        }
    }

    @objc private func openPort(_ sender: NSMenuItem) {
        guard let port = sender.representedObject as? Int,
              let url = URL(string: "http://localhost:\(port)") else { return }
        NSWorkspace.shared.open(url)
    }

    @objc private func stopPort(_ sender: NSMenuItem) {
        guard let pid = sender.representedObject as? Int else { return }
        ListeningPortsMonitor.terminate(pid: pid_t(pid), force: false)
    }

    @objc private func stopContainer(_ sender: NSMenuItem) {
        guard let name = sender.representedObject as? String else { return }
        Task.detached(priority: .userInitiated) {
            ListeningPortsMonitor.stopContainer(name)
        }
    }

    @objc private func forceStopPort(_ sender: NSMenuItem) {
        guard let pid = sender.representedObject as? Int else { return }
        ListeningPortsMonitor.terminate(pid: pid_t(pid), force: true)
    }
}
