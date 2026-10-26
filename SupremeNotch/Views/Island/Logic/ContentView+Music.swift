//
//  ContentView+Music.swift
//  SupremeNotch
//
//  Created by n0xbyte on 25.03.2026.
//

import SwiftUI
import AppKit

extension ContentView {
    @ViewBuilder
    var musicContainer: some View {
        let isWaveformActive = animationsEnabled && musicManager.isPlaying
        let wings = musicContainerWings
        let containerSize = wings.map { CGSize(width: layout.idleWidth + $0.left + $0.right, height: closedHeight) } ?? layout.islandSize
        let containerOffset = wings.map { ($0.right - $0.left) / 2 } ?? 0
        let clippedWidth = max(0, max(layout.islandSize.width, containerSize.width + abs(containerOffset) * 2) + layout.cornerRadius * 2)
        let agentEvent = displayedAgentEvent ?? agentEventManager.currentEvent
        let hasPendingAgentEvent =
            agentEvent != nil &&
            (showsAgentOverMusic || isAgentMusicTransitionActive)
        let showsAgentActivity =
            hasPendingAgentEvent &&
            isAgentMusicTransitionActive &&
            (status == .agentPreview || isAgentMusicClosing)

        Group {
            if hasPendingAgentEvent {
                AgentIslandFrame(
                    size: containerSize,
                    cornerRadius: layout.cornerRadius,
                    spacing: layout.spacing,
                    isHovered: isHovered
                ) {
                    ZStack(alignment: .top) {
                        if showsAgentActivity && showsAgentMusicContent {
                            AgentActivityView(
                                event: agentEvent,
                                size: agentActivitySize,
                                pendingCount: agentEventManager.pendingApprovals.count,
                                onDecision: { request, decision in
                                    agentEventManager.decide(request, decision)
                                },
                                onGlanceButton: { event, button in
                                    agentEventManager.handleGlanceButton(event, button)
                                }
                            )
                            .id(agentPresentationContentKey(for: agentEvent))
                            .offset(y: (isAgentMusicClosing || agentMusicContentAppeared ? 10 : 4) + layout.agentTopClearance)
                            .animation(
                                isAgentMusicClosing ? nil : .smooth(duration: 0.24, extraBounce: 0),
                                value: agentMusicContentAppeared
                            )
                        }
                    }
                    .frame(width: layout.agentPreviewSize.width + layout.cornerRadius * 2, height: layout.agentPreviewSize.height, alignment: .top)
                }
                .offset(x: containerOffset)
            } else {
                IslandContainerView(
                    size: containerSize,
                    cornerRadius: layout.cornerRadius,
                    spacing: layout.spacing,
                    shadowOpacity: status == .opened || status == .popping ? 0.2 : 0,
                    horizontalOffset: containerOffset
                ) {
            if !hidesMusicContentDuringAgentReturn && !hasPendingAgentEvent && (status == .closed ||
                status == .popping ||
                (status == .focusCollapse && focusCollapseShowsMusic && !hidesFocusStatusContentDuringReturn) ||
                (status == .brightnessCollapse && brightnessCollapseShowsMusic && !hidesBrightnessStatusContentDuringReturn) ||
                (status == .volumeCollapse && volumeCollapseShowsMusic && !hidesVolumeStatusContentDuringReturn)) {
                CompactMusicView(
                    artwork: musicManager.artworkImage,
                    waveformColor: musicManager.waveformColor,
                    isPlaying: isWaveformActive,
                    size: musicWingSize,
                    hoverOffsetY: hoverOffsetY,
                    skipIndicator: skipIndicator,
                    liveActivity: closedLiveActivity,
                    micMuted: closedMicMuted,
                    statusRing: settingsManager.showBattery ? closedStatusRing : nil,
                    horizontalOffset: musicWingOffset
                )
                .animation(.smooth(duration: 0.4, extraBounce: 0), value: closedLiveActivity)
                .opacity(tucksWings ? 0 : 1)
                .scaleEffect(x: tucksWings ? 0.6 : 1, y: tucksWings ? 0.85 : 1, anchor: .center)
                .blur(radius: tucksWings ? 2 : 0)
                .allowsHitTesting(false)
                .transition(.opacity)
                .zIndex(1)
            }

            if !hidesMusicContentDuringAgentReturn && !hasPendingAgentEvent && status == .musicPreview {
                PreviewMusicView(
                    artwork: musicManager.artworkImage,
                    combinedPreviewText: combinedPreviewText,
                    waveformColor: musicManager.waveformColor,
                    isPlaying: isWaveformActive,
                    size: layout.musicPreviewSize,
                    skipIndicator: skipIndicator
                )
                .offset(y: 10)
                .opacity(showsAgentActivity && showsAgentMusicContent ? 0 : 1)
                .scaleEffect(showsAgentActivity && showsAgentMusicContent ? 0.985 : 1)
                .animation(.smooth(duration: 0.3, extraBounce: 0), value: showsAgentMusicContent)
                .transition(.opacity.combined(with: .offset(y: 6)))
                .zIndex(2)
            }

            if status == .focusPreview || (status == .focusCollapse && !focusCollapseShowsMusic && !hidesFocusStatusContentDuringReturn) {
                FocusMusicStatusView(
                    isActive: focusStatusIsActive,
                    hidesLabel: settingsManager.hideFocusLabel,
                    size: containerSize,
                    horizontalOffset: containerOffset
                )
                .transition(.opacity.animation(.easeInOut(duration: 0.18)))
                .zIndex(4)
            }

            if status == .brightnessPreview || (status == .brightnessCollapse && !brightnessCollapseShowsMusic && !hidesBrightnessStatusContentDuringReturn) {
                BrightnessStatusView(
                    brightness: brightnessManager.brightnessLevel,
                    lineWidth: CGFloat(settingsManager.brightnessLineWidth),
                    showsLine: settingsManager.showBrightnessLine,
                    showsPercent: settingsManager.showBrightnessPercent,
                    size: containerSize,
                    horizontalOffset: containerOffset
                )
                .transition(.identity)
                .zIndex(4)
            }

            if status == .volumePreview || (status == .volumeCollapse && !volumeCollapseShowsMusic && !hidesVolumeStatusContentDuringReturn) {
                VolumeStatusView(
                    volume: musicManager.outputVolume,
                    isMuted: musicManager.isOutputMuted,
                    lineWidth: CGFloat(settingsManager.soundLineWidth),
                    showsLine: settingsManager.showSoundLine,
                    showsPercent: settingsManager.showSoundPercent,
                    size: containerSize,
                    horizontalOffset: containerOffset
                )
                .transition(.identity)
                .zIndex(4)
            }

            if status == .networkClosed || status == .networkPreview {
                NetworkStatusView(
                    event: networkStatusManager.currentEvent,
                    size: status == .networkPreview
                        ? layout.networkPreviewSize
                        : containerSize,
                    isExpanded: status == .networkPreview,
                    closedInset: StatusPreviewWings.networkInset(closedHeight: closedHeight),
                    closedOffset: containerOffset
                )
                .offset(y: 10)
                .transition(.opacity.combined(with: .offset(y: 6)))
                .zIndex(4)
            }

            if !hidesMusicContentDuringAgentReturn && status == .opened {
                ExpandedMusicView(
                    artwork: musicManager.artworkImage,
                    artworkTransitionKey: artworkTransitionKey,
                    title: musicManager.trackTitle,
                    artist: musicManager.artistName,
                    sourceName: musicManager.sourceName,
                    isPlaying: musicManager.isPlaying,
                    isShuffleEnabled: musicManager.isShuffleEnabled,
                    isShuffleControlAvailable: musicManager.isShuffleControlAvailable,
                    isLivestream: isLivestream,
                    waveformColor: musicManager.waveformColor,
                    playbackPositionText: formatPlaybackTime(musicManager.playbackPosition / 1000),
                    durationText: formatPlaybackTime(musicManager.durationMs / 1000),
                    progress: musicProgress,
                    outputVolume: musicManager.outputVolume,
                    isOutputMuted: musicManager.isOutputMuted,
                    isVolumeControlExpanded: showMusicVolumeControl,
                    size: layout.musicPlayerSize,
                    playPauseBounce: playPauseBounce,
                    accessory: micButtonAccessory,
                    onPreviewSeek: { progress in
                        musicManager.previewSeek(toProgress: progress)
                    },
                    onSeek: { progress in
                        musicManager.seek(toProgress: progress)
                    },
                    onVolumeChange: { volume in
                        musicManager.setOutputVolume(volume)
                    },
                    onToggleMute: {
                        musicManager.toggleOutputMute()
                    },
                    onToggleVolumeControl: {
                        withAnimation(animation) {
                            showMusicVolumeControl.toggle()
                        }
                    },
                    onToggleShuffle: {
                        musicManager.toggleShuffle(
                            allowSpotifyAppleScript: settingsManager.enableSpotifyAppleScriptControl,
                            allowAppleMusicAppleScript: settingsManager.enableAppleMusicAppleScriptControl
                        )
                    },
                    onPrevious: {
                        musicManager.previousTrack()
                        scheduleMusicAutoCloseAfterInteraction()
                    },
                    onTogglePlay: {
                        animatePlayPauseButton()
                        musicManager.togglePlay()
                    },
                    onNext: {
                        musicManager.nextTrack()
                        scheduleMusicAutoCloseAfterInteraction()
                    },
                    onOpenSourceApp: {
                        musicManager.openCurrentPlayerApp()
                    }
                )
                .offset(y: 20)
                .transition(ExtrasPanelView.openedContentTransition)
                .zIndex(3)

                openedSwipeCatcher

                if showsExtrasPanel {
                    ExtrasPanelView(
                        model: extrasPanelModel,
                        settingsManager: settingsManager,
                        sessionTracker: sessionTracker,
                        portsMonitor: portsMonitor,
                        audioOutputs: audioOutputManager,
                        usageMonitor: aiUsageMonitor,
                        systemMonitor: systemStatsMonitor,
                        shelf: fileShelfModel,
                        micMute: micMuteManager,
                        width: layout.musicPlayerSize.width,
                        isShelfDropTargeted: isShelfDropTargeted,
                        meeting: liveActivityModel.activity,
                        onDismissMeeting: {
                            withAnimation(.smooth(duration: 0.3, extraBounce: 0)) {
                                liveActivityModel.dismissMeeting()
                            }
                        }
                    )
                        .offset(y: layout.musicPlayerSize.height + ExtrasPanelView.gapBelowTopSection)
                        .transition(ExtrasPanelView.transition)
                        .zIndex(4)
                }
            }
                }
            }
        }
        .animation(
            animation,
            value: layout.islandSize.width
        )
        .animation(
            animation,
            value: layout.islandSize.height
        )
        .animation(
            animation,
            value: layout.cornerRadius
        )
        .animation(animation, value: containerSize.width)
        .animation(animation, value: containerOffset)
        .frame(width: clippedWidth, height: layout.islandSize.height)
        .clipped()
        .contentShape(RoundedRectangle(cornerRadius: layout.cornerRadius))
        .overlay(
            ZStack {
                if !hasPendingAgentEvent && (status == .closed || status == .musicPreview) {
                    IslandClickCatcher {
                        guard settingsManager.showMusic else { return }

                        autoExpandMusicTask?.cancel()

                        withAnimation(animation) {
                            status = .opened
                        }

                        scheduleAutoClose(after: 2.0)
                    }
                }

                if hasPendingAgentEvent && agentEvent?.approval == nil && (agentEvent?.buttons.isEmpty ?? true) {
                    IslandClickCatcher {
                        openAgentSourceApp(agentEvent)
                    }
                }

                if hasPendingAgentEvent && agentEvent?.approval == nil {
                    VStack {
                        HStack {
                            Spacer()
                            NoticeCloseButton {
                                agentEventManager.dismissCurrentEvent()
                            }
                        }
                        Spacer()
                    }
                    .padding(.top, 12 + layout.agentTopClearance)
                    .padding(.trailing, layout.cornerRadius + 10)
                    .transition(.opacity)
                }

                if status != .opened && !hasPendingAgentEvent {
                    ScrollSwipeCatcher { deltaX, deltaY in
                        handleMusicScroll(deltaX: deltaX, deltaY: deltaY)
                    }
                }
            }
        )
        .symmetricIslandResize(width: containerSize.width, offset: containerOffset, animation: animation)
    }

    /// The wings the island hugs for what the music container shows now, or nil for a
    /// state with its own size (opened, previews, collapses, tucked wings).
    var musicContainerWings: (left: CGFloat, right: CGFloat)? {
        let height = closedHeight
        func wing(_ content: CGFloat, _ inset: CGFloat) -> CGFloat {
            ClosedWings.width(content: content, inset: inset, cameraHousingInset: cameraHousingInset)
        }
        let iconWing = wing(StatusPreviewWings.iconBox, StatusPreviewWings.iconInset(closedHeight: height))
        let textInset = StatusPreviewWings.textInset(closedHeight: height)
        switch status {
        case .closed:
            guard !tucksWings else { return nil }
            return (musicLeftWingWidth, musicRightWingWidth)
        case .focusPreview:
            let label = settingsManager.hideFocusLabel ? 0 : StatusPreviewWings.focusLabelWidth(isActive: focusStatusIsActive)
            return (iconWing, wing(label, textInset))
        case .brightnessPreview:
            let right = StatusPreviewWings.levelWidth(
                showsLine: settingsManager.showBrightnessLine,
                showsPercent: settingsManager.showBrightnessPercent,
                lineWidth: CGFloat(settingsManager.brightnessLineWidth),
                percent: Int((min(max(brightnessManager.brightnessLevel, 0), 1) * 100).rounded())
            )
            return (iconWing, wing(right, textInset))
        case .volumePreview:
            let right = StatusPreviewWings.levelWidth(
                showsLine: settingsManager.showSoundLine,
                showsPercent: settingsManager.showSoundPercent,
                lineWidth: CGFloat(settingsManager.soundLineWidth),
                percent: musicManager.isOutputMuted ? 0 : Int((min(max(musicManager.outputVolume, 0), 1) * 100).rounded())
            )
            return (iconWing, wing(right, textInset))
        case .networkClosed:
            let network = wing(StatusPreviewWings.networkBox, StatusPreviewWings.networkInset(closedHeight: height))
            return (network, network)
        default:
            return nil
        }
    }

    func handleMusicScroll(deltaX: CGFloat, deltaY: CGFloat) {
        guard settingsManager.showMusic else { return }
        guard status != .focusPreview else { return }
        guard status != .focusCollapse else { return }
        guard status != .brightnessPreview else { return }
        guard status != .brightnessCollapse else { return }
        guard status != .volumePreview else { return }
        guard status != .volumeCollapse else { return }
        guard status != .networkPreview else { return }
        guard status != .networkClosed else { return }
        guard status != .networkIdle else { return }

        let horizontalTriggerThreshold: CGFloat = 14
        let verticalTriggerThreshold: CGFloat = 8
        let resetThreshold: CGFloat = 2
        let trackSwipeCooldown: TimeInterval = 0.75

        if abs(deltaX) <= resetThreshold && abs(deltaY) <= resetThreshold {
            musicScrollGestureState = 0
            return
        }

        if abs(deltaX) > abs(deltaY) {
            if deltaX < -horizontalTriggerThreshold, musicScrollGestureState == 0 {
                let now = Date.timeIntervalSinceReferenceDate
                guard now - lastMusicTrackSwipeTime >= trackSwipeCooldown else { return }

                musicScrollGestureState = 1
                lastMusicTrackSwipeTime = now
                autoExpandMusicTask?.cancel()
                performHapticFeedback()
                showSkipIndicator("forward.fill")

                musicManager.nextTrack()
                scheduleMusicAutoCloseAfterInteraction()
                return
            }

            if deltaX > horizontalTriggerThreshold, musicScrollGestureState == 0 {
                let now = Date.timeIntervalSinceReferenceDate
                guard now - lastMusicTrackSwipeTime >= trackSwipeCooldown else { return }

                musicScrollGestureState = -1
                lastMusicTrackSwipeTime = now
                autoExpandMusicTask?.cancel()
                performHapticFeedback()
                showSkipIndicator("backward.fill")

                musicManager.previousTrack()
                scheduleMusicAutoCloseAfterInteraction()
                return
            }

            return
        }

        if abs(deltaY) > abs(deltaX) {
            if deltaY > verticalTriggerThreshold, status != .opened, musicScrollGestureState == 0 {
                musicScrollGestureState = 2
                autoExpandMusicTask?.cancel()
                performHapticFeedback()

                withAnimation(animation) {
                    status = .opened
                }

                scheduleAutoClose(after: 2.0)
                return
            }

            if deltaY < -verticalTriggerThreshold, status == .opened, musicScrollGestureState == 0 {
                musicScrollGestureState = -2
                autoExpandMusicTask?.cancel()
                performHapticFeedback()

                withAnimation(animation) {
                    status = .closed
                }
                return
            }
        }
    }

    func handleMusicAutoExpand(isPlaying: Bool) {
        guard lockScreenOverlayModel.state == .music else { return }
        guard !isAgentAlertBlockingOtherEvents else { return }
        guard dynamicManager.currentModule == .music || musicManager.hasNowPlayingContent else { return }
        guard isPlaying else { return }
        guard settingsManager.showMusic else { return }
        guard status == .closed || status == .musicPreview || status == .opened else { return }

        let key = currentMusicAutoOpenKey
        guard !key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }

        if stagedMusicAutoOpenKey == key && status == .closed {
            return
        }

        let shouldStageClosedMusicPreview =
            status == .closed &&
            (musicStartUsesIdleWidth || lastMusicAutoOpenKey.isEmpty || dynamicManager.currentModule != .music)

        if shouldStageClosedMusicPreview {
            stagedMusicAutoOpenKey = key
            autoExpandMusicTask?.cancel()

            autoExpandMusicTask = Task {
                try? await Task.sleep(for: .milliseconds(520))
                guard !Task.isCancelled else { return }

                await MainActor.run {
                    guard musicManager.isPlaying else { return }
                    guard musicManager.hasNowPlayingContent else { return }
                    guard status == .closed else { return }
                    guard stagedMusicAutoOpenKey == key else { return }

                    stagedMusicAutoOpenKey = ""
                    openMusicPreview(for: key)
                }
            }
            return
        }

        if lastMusicAutoOpenKey == key && (status == .musicPreview || status == .opened) {
            return
        }

        openMusicPreview(for: key)
    }

    func openMusicPreview(for key: String) {
        guard lockScreenOverlayModel.state == .music else { return }
        lastMusicAutoOpenKey = key
        stagedMusicAutoOpenKey = ""
        autoExpandMusicTask?.cancel()

        if status == .opened {
            scheduleAutoClose(after: 2.0)
            return
        }

        previewAutoCloseKey = key

        withAnimation(animation) {
            status = .musicPreview
        }

        let scheduledKey = key
        let previewDuration = settingsManager.musicPreviewDuration

        autoExpandMusicTask = Task {
            try? await Task.sleep(for: .seconds(previewDuration))
            guard !Task.isCancelled else { return }

            await MainActor.run {
                guard !isAgentAlertBlockingOtherEvents else { return }
                guard dynamicManager.currentModule == .music || musicManager.hasNowPlayingContent else { return }
                guard status == .musicPreview else { return }
                guard previewAutoCloseKey == scheduledKey else { return }

                withAnimation(animation) {
                    status = .closed
                }
            }
        }
    }

    func handleMusicPlaybackChange(isPlaying: Bool) {
        guard settingsManager.showMusic else { return }

        if isPlaying {
            defer { lastMusicPauseDate = nil }

            guard let lastMusicPauseDate else {
                handleMusicAutoExpand(isPlaying: true)
                return
            }

            guard Date().timeIntervalSince(lastMusicPauseDate) >= 15 else { return }

            handleMusicAutoExpand(isPlaying: true)
            return
        }

        lastMusicPauseDate = Date()

        guard status == .musicPreview else { return }

        autoExpandMusicTask?.cancel()
        autoExpandMusicTask = nil
        previewAutoCloseKey = ""

        withAnimation(animation) {
            status = .closed
        }
    }

    func scheduleMusicAutoCloseAfterInteraction() {
        guard status == .opened || status == .musicPreview else { return }
        scheduleAutoClose(after: 2.0)
    }
}

/// Sizes for the Focus, brightness, volume and network notices in the closed wings: an
/// icon left of the camera, a label, level or status right of it.
enum StatusPreviewWings {
    static let iconBox: CGFloat = 24
    static let networkBox: CGFloat = 22
    static let labelFont = NSFont.systemFont(ofSize: 13, weight: .semibold)
    static let percentFont = NSFont.monospacedDigitSystemFont(ofSize: 13, weight: .semibold)

    static func iconInset(closedHeight: CGFloat) -> CGFloat {
        ClosedWings.inset(closedHeight: closedHeight, contentHeight: iconBox)
    }

    static func textInset(closedHeight: CGFloat) -> CGFloat {
        ClosedWings.inset(closedHeight: closedHeight, contentHeight: labelFont.pointSize)
    }

    static func networkInset(closedHeight: CGFloat) -> CGFloat {
        ClosedWings.inset(closedHeight: closedHeight, contentHeight: networkBox)
    }

    static func focusLabelWidth(isActive: Bool) -> CGFloat {
        ClosedWings.textWidth(isActive ? "On" : "Off", font: labelFont)
    }

    /// Digits share one width, so this changes only at 10 and 100.
    static func percentWidth(_ percent: Int) -> CGFloat {
        ClosedWings.textWidth("\(percent)", font: percentFont)
    }

    static func levelWidth(showsLine: Bool, showsPercent: Bool, lineWidth: CGFloat, percent: Int) -> CGFloat {
        if showsLine { return lineWidth }
        return showsPercent ? percentWidth(percent) : 0
    }
}

private struct FocusMusicStatusView: View {
    let isActive: Bool
    let hidesLabel: Bool
    let size: CGSize
    var horizontalOffset: CGFloat = 0

    private var accentColor: Color {
        isActive ? Color(red: 0.62, green: 0.76, blue: 1.0) : .white.opacity(0.76)
    }

    private var statusText: String {
        isActive ? "On" : "Off"
    }

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "moon.fill")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(accentColor)
                .symbolEffect(.bounce, value: isActive)
            .frame(width: 24, height: 24)

            Spacer()

            if !hidesLabel {
                Text(statusText)
                    .font(Font(StatusPreviewWings.labelFont))
                    .foregroundStyle(.white.opacity(0.9))
                    .lineLimit(1)
            }
        }
        .padding(.leading, StatusPreviewWings.iconInset(closedHeight: size.height))
        .padding(.trailing, StatusPreviewWings.textInset(closedHeight: size.height))
        .frame(width: size.width, height: size.height)
        .offset(x: horizontalOffset)
    }
}

private struct BrightnessStatusView: View {
    let brightness: Double
    let lineWidth: CGFloat
    let showsLine: Bool
    let showsPercent: Bool
    let size: CGSize
    var horizontalOffset: CGFloat = 0

    private var clampedBrightness: Double {
        min(max(brightness, 0), 1)
    }

    private var percentage: Int {
        Int((clampedBrightness * 100).rounded())
    }

    private let contentVerticalOffset: CGFloat = 1.5

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: brightnessSymbolName)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white.opacity(0.9))
                .frame(width: 24, height: 24)

            Spacer(minLength: 0)

            HStack(spacing: 4) {
                if showsLine {
                    GeometryReader { geo in
                        let width = max(geo.size.width, 1)
                        let fillWidth = width * clampedBrightness

                        ZStack(alignment: .leading) {
                            Capsule()
                                .fill(Color.white.opacity(0.16))
                                .frame(height: 5)

                            Capsule()
                                .fill(Color.white.opacity(0.88))
                                .frame(width: fillWidth, height: 5)
                                .animation(.easeOut(duration: 0.12), value: clampedBrightness)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                    .frame(width: lineWidth, height: 20)
                } else if showsPercent {
                    Text("\(percentage)")
                        .font(Font(StatusPreviewWings.percentFont))
                        .foregroundStyle(.white.opacity(0.9))
                        .fixedSize()
                }
            }
        }
        .padding(.leading, StatusPreviewWings.iconInset(closedHeight: size.height))
        .padding(.trailing, StatusPreviewWings.textInset(closedHeight: size.height))
        .frame(width: size.width, height: size.height)
        .offset(x: horizontalOffset, y: contentVerticalOffset)
    }

    private var brightnessSymbolName: String {
        switch percentage {
        case 0...25:
            return "sun.min.fill"
        case 26...75:
            return "sun.max"
        default:
            return "sun.max.fill"
        }
    }
}

private struct VolumeStatusView: View {
    let volume: Double
    let isMuted: Bool
    let lineWidth: CGFloat
    let showsLine: Bool
    let showsPercent: Bool
    let size: CGSize
    var horizontalOffset: CGFloat = 0

    private var clampedVolume: Double {
        isMuted ? 0 : min(max(volume, 0), 1)
    }

    private var percentage: Int {
        Int((clampedVolume * 100).rounded())
    }

    private let contentVerticalOffset: CGFloat = 1.5

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: volumeSymbolName)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white.opacity(0.9))
                .frame(width: 24, height: 24)

            Spacer(minLength: 0)

            HStack(spacing: 4) {
                if showsLine {
                    GeometryReader { geo in
                        let width = max(geo.size.width, 1)
                        let fillWidth = width * clampedVolume

                        ZStack(alignment: .leading) {
                            Capsule()
                                .fill(Color.white.opacity(0.16))
                                .frame(height: 5)

                            Capsule()
                                .fill(Color.white.opacity(0.88))
                                .frame(width: fillWidth, height: 5)
                                .animation(.easeOut(duration: 0.12), value: clampedVolume)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                    .frame(width: lineWidth, height: 20)
                } else if showsPercent {
                    Text("\(percentage)")
                        .font(Font(StatusPreviewWings.percentFont))
                        .foregroundStyle(.white.opacity(0.9))
                        .fixedSize()
                }
            }
        }
        .padding(.leading, StatusPreviewWings.iconInset(closedHeight: size.height))
        .padding(.trailing, StatusPreviewWings.textInset(closedHeight: size.height))
        .frame(width: size.width, height: size.height)
        .offset(x: horizontalOffset, y: contentVerticalOffset)
    }

    private var volumeSymbolName: String {
        switch percentage {
        case 0:
            return "speaker.slash.fill"
        case 1...33:
            return "speaker.wave.1.fill"
        case 34...66:
            return "speaker.wave.2.fill"
        default:
            return "speaker.wave.3.fill"
        }
    }
}
