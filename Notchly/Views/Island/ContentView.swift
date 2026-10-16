//
//  ContentView.swift
//  Notchly
//
//  Created by n0xbyte on 16.03.2026.
//

import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct ContentView: View {
    @ObservedObject var batteryManager: BatteryManager
    @ObservedObject var settingsManager: SettingsManager
    @ObservedObject var dynamicManager: DynamicManager
    @ObservedObject var musicManager: MusicManager
    @ObservedObject var focusManager: FocusManager
    @ObservedObject var brightnessManager: BrightnessManager
    @ObservedObject var networkStatusManager: NetworkStatusManager
    @ObservedObject var agentEventManager: AgentEventManager
    @ObservedObject var portsMonitor: ListeningPortsMonitor
    @ObservedObject var extrasPanelModel: ExtrasPanelModel
    @ObservedObject var sessionTracker: AgentSessionTracker
    @ObservedObject var audioOutputManager: AudioOutputManager
    @ObservedObject var liveActivityModel: LiveActivityModel
    @ObservedObject var aiUsageMonitor: AIUsageMonitor
    @ObservedObject var systemStatsMonitor: SystemStatsMonitor
    @ObservedObject var fileShelfModel: FileShelfModel
    @ObservedObject var micMuteManager: MicMuteManager
    @ObservedObject var fileDragWatcher: FileDragWatcher
    /// Files are being dragged over the notch.
    @State var isShelfDropTargeted = false
    @State var shelfDropOpenedIsland = false
    @State var hoverOpenTask: Task<Void, Never>?
    @StateObject var wingWatcher = MenuBarWingWatcher()
    /// Animated mirror of wingWatcher.isPointerBesideIsland.
    @State var wingsTuckedState = false
    @ObservedObject var lockScreenOverlayModel: LockScreenOverlayModel
    let animationsEnabled: Bool
    let onClosedHeightChange: (CGFloat) -> Void

    @State var status: IslandStatus = .closed
    @State var showChargingPop = false
    @State var isHovered = false
    @State var hasFinishedInitialAppear = false
    @State var autoExpandMusicTask: Task<Void, Never>?
    @State var focusStatusTask: Task<Void, Never>?
    @State var lastMusicAutoOpenKey: String = ""
    @State var stagedMusicAutoOpenKey: String = ""
    @State var lastMusicPauseDate: Date?
    @State var previewAutoCloseKey: String = ""
    @State var focusReturnStatus: IslandStatus = .closed
    @State var focusCollapseShowsMusic = true
    @State var focusStatusIsActive = false
    @State var hidesFocusStatusContentDuringReturn = false
    @State var pendingFocusEventIsActive = false
    @State var pendingFocusEventTimestamp: TimeInterval?
    @State var brightnessStatusTask: Task<Void, Never>?
    @State var brightnessReturnStatus: IslandStatus = .closed
    @State var brightnessCollapseShowsMusic = true
    @State var hidesBrightnessStatusContentDuringReturn = false
    @State var pendingBrightnessEventTimestamp: TimeInterval?
    @State var lastBrightnessStatusEventTime: TimeInterval = 0
    @State var volumeStatusTask: Task<Void, Never>?
    @State var volumeReturnStatus: IslandStatus = .closed
    @State var volumeCollapseShowsMusic = true
    @State var hidesVolumeStatusContentDuringReturn = false
    @State var pendingVolumeEventTimestamp: TimeInterval?
    @State var lastVolumeStatusEventTime: TimeInterval = 0
    @State var networkStatusTask: Task<Void, Never>?
    @State var pendingNetworkEventTimestamp: TimeInterval?
    @State var networkWaitsForMusicCollapse = false
    @State var musicScrollGestureState: Int = 0
    @State var lastMusicTrackSwipeTime: TimeInterval = 0
    @State var isPointerInsideIsland = false
    @State var playPauseBounce = false
    @State var skipIndicator: String?
    @State var showMusicVolumeControl = false
    @State var isAgentMusicTransitionActive = false
    @State var agentMusicReturnStatus: IslandStatus = .closed
    @State var displayedAgentEvent: AgentEvent?
    @State var agentPresentationStartedAt: Date?
    @State var agentDismissTask: Task<Void, Never>?
    @State var agentPresentationTask: Task<Void, Never>?
    @State var showsStandaloneAgentContent = false
    @State var isStandaloneAgentClosing = false
    @State var showsAgentMusicContent = false
    @State var agentMusicContentAppeared = false
    @State var hidesMusicContentDuringAgentReturn = false
    @State var agentMusicHideTask: Task<Void, Never>?
    @State var agentCollapseShowsMusic = true
    @State var isAgentMusicClosing = false
    @State var idleNotchSizeSuppressed = false
    @State var musicStartUsesIdleWidth = false
    @State var musicStartWidthTask: Task<Void, Never>?
    @State var musicEndKeepsFullWidth = false
    @State var musicEndWidthTask: Task<Void, Never>?
    @State var currentScreen: NSScreen?
    @State var resolvedClosedHeight: CGFloat = 36
    @State var presentsLockIsland = false
    @State var lockIslandWidth: CGFloat = 280
    @State var showsOpenedLockIcon = false
    @State var lockIslandTransitionTask: Task<Void, Never>?
    
    private func updateClosedHeight(for screen: NSScreen?) {
        guard lockScreenOverlayModel.state == .music else { return }

        let nextHeight = IslandHeightResolver.closedHeight(for: screen)
        if resolvedClosedHeight != nextHeight {
            resolvedClosedHeight = nextHeight
        }
        onClosedHeightChange(nextHeight)
    }

    var body: some View {
        islandViewWithScreenReader
    }

    private var islandRootView: some View {
        ZStack(alignment: .top) {
            Color.clear
                .allowsHitTesting(false)

            if presentsLockIsland {
                LockScreenIslandView(
                    islandWidth: lockIslandWidth,
                    height: closedHeight,
                    showOpenedLock: showsOpenedLockIcon
                )
                .allowsHitTesting(false)
                .zIndex(10)
            } else {
                activeModuleView
                    .padding(.top, 0)
                    .zIndex(10)
                    .scaleEffect(hoverScale, anchor: .top)
                    .onHover { hovering in
                        handleHover(hovering)
                    }
                    .onDrop(of: [.fileURL], isTargeted: $isShelfDropTargeted) { providers in
                        handleShelfDrop(providers)
                    }
                    .onChange(of: isShelfDropTargeted) { _, targeted in
                        handleShelfDropTargetChange(targeted)
                    }
                    .animation(.easeInOut(duration: 0.22), value: settingsManager.showBattery)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private var islandViewWithCoreHandlers: some View {
        islandRootView
        .onAppear {
            handleAppear()
            wingWatcher.configure(screen: currentScreen, islandWidth: wingWatcherWidth)
        }
        .onChange(of: wingWatcherWidth) { _, width in
            wingWatcher.configure(screen: currentScreen, islandWidth: width)
        }
        .onChange(of: isPointerInsideIsland || status == .opened, initial: true) { _, inUse in
            InteractionActivity.shared.setActive(inUse)
        }
        .onChange(of: settingsManager.showUsageTab, initial: true) { _, enabled in
            if enabled { aiUsageMonitor.startBackground() } else { aiUsageMonitor.stopBackground() }
        }
        .onChange(of: islandStateSnapshot, initial: true) { _, snapshot in
            IslandStateLog.record(snapshot)
        }
        .onChange(of: islandScreenFrame, initial: true) { _, frame in
            fileDragWatcher.islandFrame = frame
        }
        .onChange(of: fileDragWatcher.isNearIsland) { _, near in
            // A drop also ends "near"; that path keeps the island open longer.
            guard near || Date().timeIntervalSince(fileDragWatcher.lastDropAt) > 1 else { return }
            handleShelfDropTargetChange(near)
        }
        .onChange(of: fileDragWatcher.dropID) { _, _ in
            handleWatcherDrop(fileDragWatcher.droppedURLs)
        }
        .onDisappear {
            handleDisappear()
        }
        .onChange(of: batteryManager.isCharging) { _, newValue in
            handleChargingChange(newValue)
        }
        .onChange(of: currentMusicAutoOpenKey) { _, _ in
            handleMusicAutoExpand(isPlaying: musicManager.isPlaying)
            playPendingFocusEventIfReady()
            playPendingBrightnessEventIfReady()
            playPendingVolumeEventIfReady()
            playPendingNetworkEventIfReady()
        }
        .onChange(of: dynamicManager.currentModule) { _, _ in
            playPendingFocusEventIfReady()
            playPendingBrightnessEventIfReady()
            playPendingVolumeEventIfReady()
            playPendingNetworkEventIfReady()
        }
        .onChange(of: musicManager.isPlaying) { _, isPlaying in
            handleMusicPlaybackChange(isPlaying: isPlaying)
            playPendingFocusEventIfReady()
            playPendingBrightnessEventIfReady()
            playPendingVolumeEventIfReady()
            playPendingNetworkEventIfReady()
        }
        .onChange(of: musicManager.hasNowPlayingContent) { _, hasNowPlayingContent in
            handleNowPlayingContentChange(hasNowPlayingContent)
        }
        .onChange(of: animationsEnabled) { _, _ in
            playPendingFocusEventIfReady()
            playPendingBrightnessEventIfReady()
            playPendingVolumeEventIfReady()
            playPendingNetworkEventIfReady()
        }
        .onChange(of: lockScreenOverlayModel.state) { _, state in
            handleLockScreenStateChange(state)
        }
        .onChange(of: wingWatcher.isPointerBesideIsland) { _, beside in
            withAnimation(.smooth(duration: 0.34, extraBounce: 0)) {
                wingsTuckedState = beside
            }
        }
        .onChange(of: status) { _, newValue in
            // While you use the opened notch, new alerts wait until it closes.
            agentEventManager.setHolding(newValue == .opened)
            if newValue != .opened {
                extrasPanelModel.commitNote()
            }
            playPendingNetworkEventIfReady()
            guard newValue != .opened else { return }
            guard showMusicVolumeControl else { return }
            showMusicVolumeControl = false
        }
    }

    private var islandViewWithNotificationHandlers: some View {
        islandViewWithCoreHandlers
        .onChange(of: focusManager.focusEventID) { _, eventID in
            guard eventID > 0 else { return }
            handleFocusEvent(isActive: focusManager.focusEventIsActive)
        }
        .onChange(of: brightnessManager.brightnessEventID) { _, eventID in
            guard eventID > 0 else { return }
            handleBrightnessEvent()
        }
        .onChange(of: musicManager.outputVolumeEventID) { _, eventID in
            guard eventID > 0 else { return }
            handleVolumeEvent()
        }
        .onChange(of: activeAgentEvent == nil) { _, isGone in
            guard isGone, !isAgentMusicTransitionActive,
                  status == .agentPreview || status == .agentCollapse else { return }
            withAnimation(animation) { status = .closed }
        }
        .onChange(of: agentEventManager.eventID) { _, eventID in
            guard eventID > 0 else { return }
            handleAgentEventChange(agentEventManager.currentEvent)
        }
        .onChange(of: networkStatusManager.eventID) { _, eventID in
            guard eventID > 0, let event = networkStatusManager.currentEvent else { return }
            handleNetworkStatusEvent(event)
        }
        .onChange(of: settingsManager.showFocusAnimations) { _, isEnabled in
            guard !isEnabled else { return }
            hideFocusStatusPreview()
        }
        .onChange(of: settingsManager.showBrightnessStatus) { _, isEnabled in
            guard !isEnabled else { return }
            hideBrightnessStatusPreview()
        }
        .onChange(of: settingsManager.showSoundStatus) { _, isEnabled in
            guard !isEnabled else { return }
            hideVolumeStatusPreview()
        }
        .onChange(of: settingsManager.showNetworkStatus) { _, isEnabled in
            guard !isEnabled else { return }
            hideNetworkStatusPreview()
        }
        .onChange(of: settingsManager.showBattery) { _, isEnabled in
            handleBatteryVisibilityChange(isEnabled)
        }
        .onChange(of: settingsManager.showMusic) { _, isEnabled in
            handleMusicVisibilityChange(isEnabled)
        }
    }

    private var islandViewWithAnimations: some View {
        islandViewWithNotificationHandlers
        .animation(animation, value: status)
        .animation(.easeInOut(duration: 0.18), value: focusStatusIsActive)
        .animation(animation, value: showMusicVolumeControl)
        .animation(.easeInOut(duration: 0.22), value: batteryManager.batteryLevel)
        .preferredColorScheme(.dark)
    }

    private var islandViewWithScreenReader: some View {
        islandViewWithAnimations
        .background(
            WindowScreenReader { screen in
                guard currentScreen !== screen else { return }
                currentScreen = screen
                wingWatcher.configure(screen: screen, islandWidth: wingWatcherWidth)
                updateClosedHeight(for: screen)
            }
        )
    }
}
