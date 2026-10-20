//
//  ContentView+Computed.swift
//  Notchly
//
//  Created by n0xbyte on 25.03.2026.
//

import SwiftUI
import AppKit

extension ContentView {
    @ViewBuilder
    private var nonAgentFallbackView: some View {
        if settingsManager.showMusic && musicManager.hasNowPlayingContent {
            musicContainer
        } else if showsBaseIsland {
            islandContainer
        } else {
            emptyBar
        }
    }

    var layout: IslandLayout {
        IslandLayout(
            status: layoutStatus,
            isMusicModule: usesMusicLayout,
            showChargingPop: showChargingPop,
            isMusicVolumeControlExpanded: showMusicVolumeControl,
            closedHeight: closedHeight,
            islandWidth: effectiveIslandWidth,
            allowsCompactBaseWidth: musicStartUsesIdleWidth,
            idleWidthOverride: configuredIdleIslandWidth,
            agentContentHeight: AgentActivityView.contentHeight(
                for: activeAgentEvent,
                width: IslandLayout.baseWidth(islandWidth: effectiveIslandWidth, allowsCompact: musicStartUsesIdleWidth)
            ),
            agentTopClearance: agentTopClearance,
            openedExtraHeight: showsExtrasPanel ? extrasPanelHeight + ExtrasPanelView.gapBelowTopSection : 0,
            wingsTucked: tucksWings,
            liveActivityExtraWidth: liveActivityExtraWidth,
            batteryWingWidth: CompactBatteryView.chargingWingWidth(
                closedHeight: closedHeight,
                cameraHousingInset: cameraHousingInset
            ),
            preferredOpenedWidth: preferredOpenedWidth
        )
    }

    /// The opened notch sizes itself to the selected tab, so short tabs get a narrower
    /// island. The music player needs 372 to fit its controls beside the mic button.
    var preferredOpenedWidth: CGFloat? {
        guard showsExtrasPanel, let tab = selectedExtrasTab else { return nil }
        let wanted: CGFloat
        switch tab {
        case .agents:
            // Grows to fit the longest session name and step, up to the window's limit.
            let sessions = Array(sessionTracker.sessions.prefix(6))
            wanted = min(max(AgentRowMetrics.contentWidth(for: sessions) + 2 * (IslandMetrics.rowEdgeInset + IslandMetrics.rowContentPadding), 384), IslandLayout.maxOpenedWidth)
        case .ports, .system, .shelf, .usage:
            wanted = 384
        case .note, .output:
            wanted = 344
        case .ask:
            // Room to read an answer.
            wanted = 460
        }
        return usesMusicLayout ? max(wanted, 372) : wanted
    }

    /// The mic button for the battery panel or music controls row, when it is turned on.
    var micButtonAccessory: AnyView? {
        guard settingsManager.showMicMute, micMuteManager.hasInput else { return nil }
        return AnyView(MicMuteButton(micMute: micMuteManager))
    }

    /// The meeting countdown to show in the closed wings, if any. Glances, the charging pop
    /// and an opened island take precedence.
    var closedLiveActivity: LiveActivity? {
        guard status == .closed, activeAgentEvent == nil, !showChargingPop,
              !isAgentMusicTransitionActive else { return nil }
        guard let activity = liveActivityModel.activity else { return nil }
        if usesMusicLayout || dynamicManager.currentModule == .music {
            return settingsManager.showMusic && musicManager.hasNowPlayingContent ? activity : nil
        }
        return dynamicManager.currentModule == .battery && showsBaseIsland ? activity : nil
    }

    /// The battery wings carry a title, so they widen more than the music badge needs.
    /// Capped so the island stays inside its 456 pt window.
    var liveActivityExtraWidth: CGFloat {
        guard closedLiveActivity != nil else { return 0 }
        let wanted: CGFloat = dynamicManager.currentModule == .music || usesMusicLayout ? 40 : 100
        let base = min(max(CGFloat(settingsManager.islandWidth), 280), 360)
        return max(0, min(wanted, 420 - base))
    }

    var wingWatcherWidth: CGFloat {
        layout.baseWidth + liveActivityExtraWidth
    }

    /// The closed battery island shows only the status ring, in a wing right of the camera
    /// notch; its left edge stays flush with the notch.
    var usesBatterySideWing: Bool {
        status == .closed && closedLiveActivity == nil && !usesIdleNotchSize && !tucksWings
    }

    /// The ring's wing, right of the camera.
    /// How far in from the reported notch edges the closed notch's glyphs may sit.
    var cameraHousingInset: CGFloat {
        CompactBatteryView.defaultCameraHousingInset - CGFloat(settingsManager.cameraSpacingAdjustment)
    }

    /// The base island, around the camera: the battery ring, the usage bars or the muted
    /// mic. Turning the battery off hides only the ring.
    var showsBaseIsland: Bool {
        settingsManager.showBattery || !closedUsageBars.isEmpty || closedMicMuted
    }

    /// The ring's wing, right of the camera; none while the battery is turned off.
    var batterySideWingWidth: CGFloat {
        guard settingsManager.showBattery else { return 0 }
        return CompactBatteryView.wingWidth(closedHeight: closedHeight, cameraHousingInset: cameraHousingInset)
    }

    var closedMicMuted: Bool {
        settingsManager.showMicMute && micMuteManager.isMuted
    }

    /// Subscription usage for the closed notch: Claude's limits, then Codex, leaving out
    /// any turned off in Settings > AI Usage.
    var closedUsageBars: [UsageBar] {
        guard settingsManager.showUsageTab, case let .loaded(snapshot) = aiUsageMonitor.state else { return [] }
        var bars = snapshot.claude
            .filter { settingsManager.showsUsageBar($0.kind) }
            .map { UsageBar(id: $0.label, percent: $0.percent, scale: .claude) }
        bars += snapshot.codexWindows
            .filter { settingsManager.showsUsageBar($0.kind) }
            .map { UsageBar(id: $0.label, percent: $0.percent, scale: .codex) }
        return bars
    }

    /// The wing left of the camera, for the usage bars and the muted mic.
    var batteryLeftWingWidth: CGFloat {
        CompactBatteryView.leftWingWidth(
            barCount: closedUsageBars.count,
            micMuted: closedMicMuted,
            closedHeight: closedHeight,
            cameraHousingInset: cameraHousingInset
        )
    }

    var batterySideWingSize: CGSize {
        CGSize(width: layout.idleWidth + batterySideWingWidth + batteryLeftWingWidth, height: closedHeight)
    }

    /// The closed notch's status ring, for the music island's right wing.
    var closedStatusRing: StatusRingGlyph {
        StatusRingGlyph(
            batteryLevel: batteryManager.batteryLevel,
            isCharging: batteryManager.isCharging,
            lowBatteryThreshold: settingsManager.lowBatteryThreshold,
            network: networkStatusManager.glyphState,
            volume: musicManager.outputVolume,
            isMuted: musicManager.isOutputMuted,
            height: CompactBatteryView.glyphHeight(closedHeight: closedHeight),
            isLowPowerMode: batteryManager.isLowPowerMode,
            isChargeOnHold: batteryManager.isChargeOnHold,
            chargeHoldStyle: settingsManager.chargeHoldStyle
        )
    }

    /// Closed music: the artwork's wing left of the camera.
    var musicLeftWingWidth: CGFloat {
        CompactMusicView.leftWingWidth(
            micMuted: closedMicMuted,
            closedHeight: closedHeight,
            cameraHousingInset: cameraHousingInset
        )
    }

    /// Closed music: the right wing holds a meeting countdown, the ring, or the waveform
    /// with the battery turned off.
    var musicRightWingWidth: CGFloat {
        if let activity = closedLiveActivity {
            return LiveActivityBadge.wingWidth(for: activity, closedHeight: closedHeight, cameraHousingInset: cameraHousingInset)
        }
        return settingsManager.showBattery
            ? batterySideWingWidth
            : CompactMusicView.waveformWingWidth(closedHeight: closedHeight, cameraHousingInset: cameraHousingInset)
    }

    var musicWingSize: CGSize {
        CGSize(width: layout.idleWidth + musicLeftWingWidth + musicRightWingWidth, height: closedHeight)
    }

    var musicWingOffset: CGFloat {
        (musicRightWingWidth - musicLeftWingWidth) / 2
    }

    var agentTopClearance: CGFloat {
        AgentActivityView.notchClearance(
            closedHeight: closedHeight,
            screenHasNotch: (currentScreen?.safeAreaInsets.top ?? 0) > 0
        )
    }

    /// The alert body's size: the island's alert size without the room above the header.
    var agentActivitySize: CGSize {
        let size = layout.agentPreviewSize
        return CGSize(width: size.width, height: size.height - layout.agentTopClearance)
    }

    var batterySideWingOffset: CGFloat {
        (batterySideWingWidth - batteryLeftWingWidth) / 2
    }

    /// An agent alert grows out of, and shrinks back into, the battery wing when that is
    /// what the closed notch shows around it; otherwise the island would jump in width.
    var agentClosedUsesBatteryWing: Bool {
        showsBaseIsland && closedLiveActivity == nil && !showChargingPop
            && !(settingsManager.showMusic && musicManager.hasNowPlayingContent)
    }

    /// Shrink the closed island to the camera notch while the pointer is beside it.
    var tucksWings: Bool {
        status == .closed && wingsTuckedState && activeAgentEvent == nil && !showChargingPop
            && !fileDragWatcher.isFileDragActive
    }

    /// The tabbed panel (agents, ports, note, output) under the battery panel or music player.
    var showsExtrasPanel: Bool {
        guard selectedExtrasTab != nil else { return false }
        if usesMusicLayout {
            return settingsManager.showMusic && musicManager.hasNowPlayingContent && activeAgentEvent == nil
        }
        switch dynamicManager.currentModule {
        case .battery:
            return true
        case .agent:
            // The battery panel is also the fallback while the module catches up after a glance.
            return activeAgentEvent == nil && showsBaseIsland
        case .music, .none:
            return false
        }
    }

    /// Catches sideways swipes anywhere on the opened notch, not just over the tabs, and
    /// sits behind everything so buttons and sliders keep their own input.
    @ViewBuilder
    var openedSwipeCatcher: some View {
        if status == .opened, showsExtrasPanel, !SnapshotRendering.isActive {
            ScrollSwipeCatcher(onScrollEvent: { event in
                extrasPanelModel.handleSwipe(
                    event,
                    tabs: extrasPanelModel.availableTabs(settingsManager),
                    selected: selectedExtrasTab
                )
            })
            .frame(width: layout.islandSize.width, height: layout.islandSize.height)
            .zIndex(0)
        }
    }

    var selectedExtrasTab: ExtrasPanelModel.Tab? {
        extrasPanelModel.resolvedTab(
            available: extrasPanelModel.availableTabs(settingsManager),
            activeSessions: sessionTracker.activeCount
        )
    }

    var extrasPanelHeight: CGFloat {
        ExtrasPanelView.height(
            tab: selectedExtrasTab,
            sessions: sessionTracker.sessions.count,
            ports: portsMonitor.panelPorts.count,
            outputs: audioOutputManager.devices.count,
            usageRows: aiUsageMonitor.rowCount,
            shelfItems: fileShelfModel.items.count,
            askHasConversation: extrasPanelModel.askAI.hasConversation,
            hasMeeting: liveActivityModel.activity != nil
        )
    }

    /// TEMPORARY: the state that decides what the island shows, for IslandStateLog.
    var islandStateSnapshot: String {
        "status=\(status) module=\(dynamicManager.currentModule) lock=\(lockScreenOverlayModel.state)"
            + " lockIsland=\(presentsLockIsland) idle=\(usesIdleNotchSize) tucked=\(tucksWings)"
            + " sideWing=\(usesBatterySideWing) chargingPop=\(showChargingPop)"
            + " resolving=\(musicManager.isResolvingNowPlaying) nowPlaying=\(musicManager.hasNowPlayingContent)"
            + " agent=\(activeAgentEvent?.kind.rawValue ?? "-")/\(agentEventManager.currentEvent?.kind.rawValue ?? "-")"
            + " hover=\(isHovered)"
    }

    var activeModuleView: some View {
        Group {
            let hasActiveAgentEvent = activeAgentEvent != nil

            if isAgentMusicTransitionActive {
                musicContainer
            } else if isStandaloneAgentPresentationActive {
                agentContainer
            } else if dynamicManager.currentModule == .agent,
                      agentEventManager.currentEvent == nil,
                      settingsManager.showMusic,
                      musicManager.hasNowPlayingContent {
                musicContainer
            } else if dynamicManager.currentModule == .agent, hasActiveAgentEvent {
                agentContainer
            } else if status == .focusCollapse ||
                status == .focusPreview ||
                status == .brightnessCollapse ||
                status == .brightnessPreview ||
                status == .volumeCollapse ||
                status == .volumePreview ||
                status == .networkIdle ||
                status == .networkClosed ||
                status == .networkPreview {
                musicContainer
            } else if settingsManager.showMusic &&
                musicManager.hasNowPlayingContent &&
                (musicStartUsesIdleWidth || !stagedMusicAutoOpenKey.isEmpty) {
                musicContainer
            } else {
                switch dynamicManager.currentModule {
                case .agent:
                    if hasActiveAgentEvent {
                        agentContainer
                    } else {
                        nonAgentFallbackView
                    }
                case .battery:
                    if showsBaseIsland {
                        islandContainer
                    } else {
                        emptyBar
                    }
                case .music:
                    musicContainer
                case .none:
                    emptyBar
                }
            }
        }
    }

    var layoutStatus: IslandStatus {
        return status
    }

    var usesMusicLayout: Bool {
        if dynamicManager.currentModule == .music || isAgentMusicTransitionActive {
            return true
        }

        guard settingsManager.showMusic,
              musicManager.hasNowPlayingContent else { return false }

        switch status {
        case .opened, .musicPreview, .agentCollapse, .agentPreview:
            return true
        case .closed, .popping, .focusCollapse, .focusPreview, .brightnessCollapse, .brightnessPreview, .volumeCollapse, .volumePreview, .networkIdle, .networkClosed, .networkPreview:
            return false
        }
    }

    var canShowAgentOverMusic: Bool {
        guard settingsManager.showMusic else { return false }
        guard musicManager.isPlaying else { return false }
        guard musicManager.hasNowPlayingContent else { return false }

        switch status {
        case .closed, .opened, .musicPreview:
            return true
        case .popping, .focusCollapse, .focusPreview, .brightnessCollapse, .brightnessPreview, .volumeCollapse, .volumePreview, .networkIdle, .networkClosed, .networkPreview, .agentCollapse, .agentPreview:
            return false
        }
    }

    var showsAgentOverMusic: Bool {
        agentEventManager.currentEvent != nil && canShowAgentOverMusic
    }

    var activeAgentEvent: AgentEvent? {
        displayedAgentEvent ?? agentEventManager.currentEvent
    }

    var isStandaloneAgentPresentationActive: Bool {
        guard !isAgentMusicTransitionActive else { return false }
        guard activeAgentEvent != nil else { return false }
        return status == .agentPreview || status == .agentCollapse
    }

    var isAgentAlertBlockingOtherEvents: Bool {
        activeAgentEvent != nil || isAgentMusicTransitionActive
    }

    var closedHeight: CGFloat {
        resolvedClosedHeight
    }

    var configuredBaseIslandWidth: CGFloat {
        min(max(CGFloat(settingsManager.islandWidth), 280), 360)
    }

    var configuredIdleIslandWidth: CGFloat {
        IslandWidthResolver.idleWidth(
            for: currentScreen,
            configuredIslandWidth: configuredBaseIslandWidth
        )
    }

    var effectiveIslandWidth: CGFloat {
        guard musicStartUsesIdleWidth,
              status == .closed else {
            return CGFloat(settingsManager.islandWidth)
        }

        return configuredIdleIslandWidth + (isHovered ? 8 : 0)
    }

    var usesIdleNotchSize: Bool {
        guard status == .closed else { return false }
        guard !idleNotchSizeSuppressed else { return false }
        if activeAgentEvent != nil {
            return canUseCompactAgentClosedSize
        }
        guard !showChargingPop else { return false }
        guard !musicEndKeepsFullWidth else { return false }
        guard !musicStartUsesIdleWidth else { return true }
        guard !(settingsManager.showMusic && musicManager.hasNowPlayingContent) else { return false }

        switch dynamicManager.currentModule {
        case .none:
            return true
        case .agent:
            return agentEventManager.currentEvent == nil
        case .battery:
            // Nothing to show around the camera: the plain notch.
            return !showsBaseIsland
        case .music:
            return false
        }
    }

    var canUseCompactAgentClosedSize: Bool {
        guard status == .closed else { return false }
        guard !idleNotchSizeSuppressed else { return false }
        guard !showChargingPop else { return false }
        guard !musicEndKeepsFullWidth else { return false }
        guard !musicStartUsesIdleWidth else { return false }
        guard !(settingsManager.showMusic && musicManager.hasNowPlayingContent) else { return false }

        switch dynamicManager.currentModule {
        case .none, .agent:
            return true
        case .battery:
            return !showsBaseIsland
        case .music:
            return false
        }
    }

    var idleNotchSize: CGSize {
        usesIdleNotchSize && isHovered ? layout.idleHoverSize : layout.idleSize
    }

    var hoverScale: CGFloat {
        if usesIdleNotchSize {
            return 1.0
        }

        guard isHovered else { return 1.0 }

        switch status {
        case .closed:
            return 1.02
        case .popping:
            return 1.02
        case .opened:
            return 1.012
        case .musicPreview:
            return 1.01
        case .focusCollapse:
            return 1.0
        case .focusPreview:
            return 1.01
        case .brightnessCollapse:
            return 1.0
        case .brightnessPreview:
            return 1.01
        case .volumeCollapse:
            return 1.0
        case .volumePreview:
            return 1.01
        case .networkIdle:
            return 1.0
        case .networkClosed:
            return 1.0
        case .networkPreview:
            return 1.01
        case .agentCollapse:
            return 1.0
        case .agentPreview:
            return 1.01
        }
    }

    var hoverOffsetY: CGFloat {
        return isHovered ? 3 : 0
    }

    var currentMusicAutoOpenKey: String {
        [
            musicManager.trackTitle,
            musicManager.artistName,
            musicManager.albumTitle,
            musicManager.sourceName
        ].joined(separator: "|")
    }

    var artworkTransitionKey: String {
        "\(musicManager.trackTitle)|\(musicManager.artistName)|\(musicManager.albumTitle)"
    }

    var musicProgress: CGFloat {
        guard musicManager.durationMs > 0 else { return 0 }
        return CGFloat(min(max(musicManager.playbackPosition / musicManager.durationMs, 0), 1))
    }

    var isLivestream: Bool {
        musicManager.durationMs <= 0
    }

    var combinedPreviewText: String {
        let title = musicManager.trackTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        let artist = musicManager.artistName.trimmingCharacters(in: .whitespacesAndNewlines)

        if !title.isEmpty && !artist.isEmpty {
            return "\(title) — \(artist)"
        } else if !title.isEmpty {
            return title
        } else if !artist.isEmpty {
            return artist
        } else {
            return "Now Playing"
        }
    }

    var animation: Animation {
        .interactiveSpring(duration: 0.5, extraBounce: 0.01, blendDuration: 0.125)
    }

    var agentMusicHeightAnimation: Animation {
        .smooth(duration: 0.68, extraBounce: 0)
    }
    
    func formatPlaybackTime(_ totalSeconds: TimeInterval) -> String {
        let seconds = max(0, Int(totalSeconds.rounded()))
        let hours = seconds / 3600
        let minutes = (seconds % 3600) / 60
        let secs = seconds % 60

        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, secs)
        } else {
            return String(format: "%d:%02d", minutes, secs)
        }
    }
}
