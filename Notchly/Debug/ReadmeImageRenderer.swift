//
//  ReadmeImageRenderer.swift
//  BetterNotch
//
//  Debug builds only: `BetterNotch -renderReadmeImages <folder>` fills the real views
//  with sample data, writes the README images there and quits. Debug builds use their
//  own bundle ID, so this never touches the installed app's settings or keys.
//

#if DEBUG
import AppKit
import CoreAudio
import SwiftUI

@MainActor
enum ReadmeImageRenderer {
    static var outputDirectory: URL? {
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: "-renderReadmeImages"), index + 1 < arguments.count else { return nil }
        return URL(fileURLWithPath: arguments[index + 1], isDirectory: true)
    }

    static func render(environment: AppEnvironment, to directory: URL) {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        SnapshotRendering.isActive = true
        loadSamples(into: environment)

        for tab in [ExtrasPanelModel.Tab.agents, .usage, .system, .ports, .shelf, .output] {
            environment.extrasPanelModel.choose(tab)
            save(Backdrop { OpenedIsland(environment: environment, tab: tab) }, as: "tab-\(tab.rawValue).png", in: directory)
            save(PanelCard(environment: environment, tab: tab), as: "panel-\(tab.rawValue).png", in: directory)
        }

        // Spacing check: every row's hover highlight drawn, not used in the README.
        SnapshotRendering.showsRowHighlights = true
        environment.extrasPanelModel.choose(.agents)
        save(Backdrop { OpenedIsland(environment: environment, tab: .agents) }, as: "check-row-highlights.png", in: directory)
        SnapshotRendering.showsRowHighlights = false

        // The Ask tab, empty (a check) and with a conversation (in the README).
        environment.settingsManager.showAskAI = true
        environment.extrasPanelModel.choose(.ask)
        save(Backdrop { OpenedIsland(environment: environment, tab: .ask) }, as: "check-ask-empty.png", in: directory)
        environment.extrasPanelModel.askAI.previewLoad([
            ("What is the tallest mountain in Africa?", "Mount Kilimanjaro in Tanzania, at **5,895 m** (19,341 ft) above sea level."),
            ("How long does it usually take to climb it?", "Most climbs take **5 to 9 days** including the descent. Longer routes, like the 8-day Lemosho, give you more time to acclimatize and raise your chance of reaching the summit.")
        ])
        save(Backdrop { OpenedIsland(environment: environment, tab: .ask) }, as: "tab-ask.png", in: directory)
        environment.extrasPanelModel.askAI.clear()

        // Settings check: the usage bar style picker, not used in the README.
        save(AIUsageSettingsView(settingsManager: environment.settingsManager)
                .frame(width: 560).padding(20).background(Color(white: 0.16)).environment(\.colorScheme, .dark),
             as: "check-usage-settings.png", in: directory)
        environment.settingsManager.cameraSpacingAdjustment = 1.5
        save(GeneralSettingsView(settingsManager: environment.settingsManager,
                                 lockScreenIdentityManager: environment.lockScreenIdentityManager)
                .frame(width: 560).padding(20).background(Color(white: 0.16)).environment(\.colorScheme, .dark),
             as: "check-general-settings.png", in: directory)
        environment.settingsManager.cameraSpacingAdjustment = 0

        let now = Date()
        let approval = AgentApprovalRequest(
            id: "sample", source: "claude", sessionID: "s1", toolName: "Bash",
            toolLabel: "Run command", summary: "npm run build && npm test",
            detail: "Builds the site, then runs the test suite", project: "better-notch",
            receivedAt: now, deadline: now.addingTimeInterval(60)
        )
        let openSession = GlanceButton(title: "Open session", systemImage: "arrow.up.forward.app",
                                       isPrimary: true, action: .openSession(id: "s1", source: "claude"))
        let notices: [(String, AgentEvent)] = [
            ("notice-approval.png", AgentEvent(id: UUID(), source: "claude", kind: .accessRequest, title: "Needs approval",
                                                message: nil, ttl: 60, createdAt: now, approval: approval)),
            ("notice-question.png", AgentEvent(id: UUID(), source: "claude", kind: .waiting,
                                                title: "Claude asked a question · better-notch", message: nil, ttl: 30,
                                                createdAt: now, detail: "Should the usage bars refresh every 5 minutes or every 2?",
                                                buttons: [openSession], sessionID: "s1")),
            ("notice-finished.png", AgentEvent(id: UUID(), source: "claude", kind: .completed,
                                                title: "Claude finished · better-notch", message: nil, ttl: 8,
                                                createdAt: now, detail: "Moved the status ring to the right wing and added color-coded usage bars.",
                                                buttons: [openSession], sessionID: "s1"))
        ]
        for (name, event) in notices {
            save(Backdrop { NoticeIsland(event: event) }, as: name, in: directory)
        }
    }

    private static func loadSamples(into environment: AppEnvironment) {
        let now = Date()
        let settings = environment.settingsManager
        settings.showUsageTab = true
        settings.showSystemTab = true
        settings.showFileShelf = true
        settings.showPortsPanel = true

        var usage = AIUsageSnapshot()
        usage.claude = [
            UsageWindow(label: "5 hours", percent: 34, resetsAt: now.addingTimeInterval(2 * 3600 + 600)),
            UsageWindow(label: "Week", percent: 61, resetsAt: now.addingTimeInterval(3 * 86400 + 5 * 3600)),
            UsageWindow(label: "Fable", percent: 18, resetsAt: now.addingTimeInterval(3 * 86400 + 5 * 3600))
        ]
        usage.codex = UsageWindow(label: "Codex", percent: 27, resetsAt: now.addingTimeInterval(5 * 86400))
        environment.aiUsageMonitor.previewLoad(usage)

        environment.agentEventManager.sessionTracker.previewLoad([
            AgentSession(id: "s1", source: "claude", project: "better-notch", pid: nil, state: .working,
                         stateSince: now.addingTimeInterval(-312), currentStep: "Editing StatusRingGlyph.swift", lastActivity: now),
            AgentSession(id: "s2", source: "codex", project: "referenced-chatgpt-conversation", title: "Create heating prototype snapshot",
                         pid: nil, state: .working, stateSince: now.addingTimeInterval(-40),
                         currentStep: AgentSessionTracker.stepText(toolName: "exec_command", hint: "cmd:*** Begin"),
                         lastActivity: now),
            AgentSession(id: "s3", source: "claude", project: "docs-site", pid: nil, state: .waiting,
                         stateSince: now.addingTimeInterval(-95), currentStep: nil, lastActivity: now),
            AgentSession(id: "s4", source: "claude", project: "infra", pid: nil, state: .done,
                         stateSince: now.addingTimeInterval(-600), currentStep: nil, lastActivity: now)
        ])

        let gigabyte: UInt64 = 1 << 30
        let history = (0..<60).map { index -> NetworkSample in
            let t = Double(index)
            return NetworkSample(
                at: now.addingTimeInterval(-300 + t * 5),
                downBytesPerSecond: (1.4 + 1.1 * sin(t / 6) + (index % 11 == 0 ? 2.2 : 0)) * 1_000_000,
                upBytesPerSecond: (0.18 + 0.12 * cos(t / 4)) * 1_000_000
            )
        }
        environment.systemStatsMonitor.previewLoad(
            stats: SystemStats(cpuPercent: 23, memoryUsedBytes: 14 * gigabyte + gigabyte / 4,
                               memoryTotalBytes: 24 * gigabyte, diskUsedBytes: 412 * 1_000_000_000,
                               diskTotalBytes: 994 * 1_000_000_000),
            history: history
        )

        environment.portsMonitor.previewLoad([
            ListeningPort(pid: 4101, port: 3000, command: "node", project: "better-notch-site"),
            ListeningPort(pid: 4102, port: 5173, command: "vite", project: "dashboard"),
            ListeningPort(pid: 4103, port: 8000, command: "python3", project: "api-server"),
            ListeningPort(pid: 4104, port: 5432, command: "com.docker.backend", project: nil,
                          dockerContainer: "api-db-1", dockerService: "postgres", dockerProject: "api")
        ])

        let shelfFolder = FileManager.default.temporaryDirectory.appendingPathComponent("readme-shelf", isDirectory: true)
        try? FileManager.default.createDirectory(at: shelfFolder, withIntermediateDirectories: true)
        let files = ["Roadmap.pdf", "Notch mockup.png", "release-notes.md", "Demo.mov"].map { shelfFolder.appendingPathComponent($0) }
        for file in files where !FileManager.default.fileExists(atPath: file.path) {
            FileManager.default.createFile(atPath: file.path, contents: Data())
        }
        environment.fileShelfModel.previewLoad(files)

        environment.audioOutputManager.previewLoad([
            AudioOutputDevice(id: 1, name: "MacBook Pro Speakers", transport: kAudioDeviceTransportTypeBuiltIn),
            AudioOutputDevice(id: 2, name: "AirPods Pro", transport: kAudioDeviceTransportTypeBluetooth),
            AudioOutputDevice(id: 3, name: "Studio Display", transport: kAudioDeviceTransportTypeDisplayPort)
        ], defaultID: 2)
    }

    private static func save<V: View>(_ view: V, as name: String, in directory: URL) {
        let renderer = ImageRenderer(content: view.environment(\.colorScheme, .dark))
        renderer.scale = 2
        guard let image = renderer.cgImage,
              let data = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]) else { return }
        try? data.write(to: directory.appendingPathComponent(name))
    }
}

/// A soft desktop-like background around each island.
private struct Backdrop<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        content
            .padding(.horizontal, 28)
            .padding(.bottom, 26)
            .background(
                LinearGradient(colors: [Color(red: 0.10, green: 0.12, blue: 0.20), Color(red: 0.20, green: 0.14, blue: 0.24)],
                               startPoint: .topLeading, endPoint: .bottomTrailing)
            )
    }
}

/// The opened notch as ContentView lays it out: battery panel, then the tab panel.
private struct OpenedIsland: View {
    let environment: AppEnvironment
    let tab: ExtrasPanelModel.Tab

    var body: some View {
        let width: CGFloat = tab == .agents
            ? min(max(AgentRowMetrics.contentWidth(for: environment.agentEventManager.sessionTracker.sessions) + 2 * (IslandMetrics.rowEdgeInset + IslandMetrics.rowContentPadding), 384), IslandLayout.maxOpenedWidth)
            : (tab == .ask ? 460 : 384)
        let extras = ExtrasPanelView.height(
            tab: tab,
            sessions: environment.agentEventManager.sessionTracker.sessions.count,
            ports: environment.portsMonitor.panelPorts.count,
            outputs: environment.audioOutputManager.devices.count,
            usageRows: environment.aiUsageMonitor.rowCount,
            shelfItems: environment.fileShelfModel.items.count,
            askHasConversation: environment.extrasPanelModel.askAI.hasConversation
        )
        let height = 20 + 132 - 12 + extras
        ZStack(alignment: .top) {
            UnevenRoundedRectangle(bottomLeadingRadius: IslandMetrics.openedRadius, bottomTrailingRadius: IslandMetrics.openedRadius)
                .fill(Color.black)
                .frame(width: width, height: height)

            ExpandedBatteryView(
                batteryLevel: 82, isCharging: false, lowBatteryThreshold: 20,
                network: .wifi(.strong), volume: 0.55, isVolumeMuted: false,
                size: CGSize(width: width, height: 132),
                accessory: AnyView(MicMuteButton(micMute: environment.micMuteManager))
            )
            .offset(y: 20)

            ExtrasPanelView(
                model: environment.extrasPanelModel,
                settingsManager: environment.settingsManager,
                sessionTracker: environment.agentEventManager.sessionTracker,
                portsMonitor: environment.portsMonitor,
                audioOutputs: environment.audioOutputManager,
                usageMonitor: environment.aiUsageMonitor,
                systemMonitor: environment.systemStatsMonitor,
                shelf: environment.fileShelfModel,
                micMute: environment.micMuteManager,
                width: width
            )
            .offset(y: 20 + 132 - 12)
        }
        .frame(width: width, height: height, alignment: .top)
    }
}

/// Just the tab panel, for showing several tabs side by side.
private struct PanelCard: View {
    let environment: AppEnvironment
    let tab: ExtrasPanelModel.Tab

    var body: some View {
        let width: CGFloat = 384
        let height = ExtrasPanelView.height(
            tab: tab,
            sessions: environment.agentEventManager.sessionTracker.sessions.count,
            ports: environment.portsMonitor.panelPorts.count,
            outputs: environment.audioOutputManager.devices.count,
            usageRows: environment.aiUsageMonitor.rowCount,
            shelfItems: environment.fileShelfModel.items.count
        )
        ExtrasPanelView(
            model: environment.extrasPanelModel,
            settingsManager: environment.settingsManager,
            sessionTracker: environment.agentEventManager.sessionTracker,
            portsMonitor: environment.portsMonitor,
            audioOutputs: environment.audioOutputManager,
            usageMonitor: environment.aiUsageMonitor,
            systemMonitor: environment.systemStatsMonitor,
            shelf: environment.fileShelfModel,
            micMute: environment.micMuteManager,
            width: width
        )
        .padding(.top, 10)
        .frame(width: width, height: height + 10, alignment: .top)
        .background(Color.black, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
        .padding(14)
        .background(Color(red: 0.13, green: 0.13, blue: 0.18))
    }
}

/// An agent alert as it drops out of the notch.
private struct NoticeIsland: View {
    let event: AgentEvent

    var body: some View {
        let size = CGSize(width: 340, height: AgentActivityView.contentHeight(for: event, width: 340) ?? 68)
        ZStack(alignment: .top) {
            UnevenRoundedRectangle(bottomLeadingRadius: IslandMetrics.noticeRadius, bottomTrailingRadius: IslandMetrics.noticeRadius)
                .fill(Color.black)
                .frame(width: size.width, height: size.height)
            AgentActivityView(event: event, size: size)
                .offset(y: AgentActivityView.contentTopOffset)
        }
        .frame(width: size.width, height: size.height, alignment: .top)
        .clipped()
    }
}
#endif
