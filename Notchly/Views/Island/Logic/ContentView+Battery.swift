//
//  ContentView+Battery.swift
//  Notchly
//
//  Created by n0xbyte on 25.03.2026.
//

import SwiftUI

extension ContentView {
    var emptyBar: some View {
        EmptyIslandView(
            size: usesIdleNotchSize ? idleNotchSize : layout.closedSize,
            cornerRadius: layout.cornerRadius,
            spacing: layout.spacing,
            isHovered: isHovered
        )
        .animation(.smooth(duration: 0.22, extraBounce: 0), value: isHovered)
        .animation(animation, value: usesIdleNotchSize)
    }

    var islandContainer: some View {
        let leftOnly = usesBatterySideWing
        let containerSize = leftOnly ? batterySideWingSize
            : (usesIdleNotchSize ? idleNotchSize : layout.islandSize)
        let compactContentSize = usesIdleNotchSize ? idleNotchSize : layout.closedSize

        return IslandContainerView(
            size: containerSize,
            cornerRadius: layout.cornerRadius,
            spacing: layout.spacing,
            shadowOpacity: status == .opened || status == .popping ? 0.2 : 0,
            horizontalOffset: leftOnly ? batterySideWingOffset : 0
        ) {
            if status == .closed, let liveActivity = closedLiveActivity {
                LiveActivityWingsView(
                    activity: liveActivity,
                    size: compactContentSize,
                    notchWidth: configuredIdleIslandWidth,
                    hoverOffsetY: hoverOffsetY
                )
                .opacity(tucksWings ? 0 : 1)
                .scaleEffect(x: tucksWings ? 0.6 : 1, y: tucksWings ? 0.85 : 1, anchor: .center)
                .blur(radius: tucksWings ? 2 : 0)
                .allowsHitTesting(false)
                .transition(.opacity)
                .zIndex(1)
            } else if status == .closed {
                CompactBatteryView(
                    batteryLevel: batteryManager.batteryLevel,
                    isCharging: batteryManager.isCharging,
                    lowBatteryThreshold: settingsManager.lowBatteryThreshold,
                    network: networkStatusManager.glyphState,
                    volume: musicManager.outputVolume,
                    isVolumeMuted: musicManager.isOutputMuted,
                    size: leftOnly ? batterySideWingSize : compactContentSize,
                    horizontalOffset: leftOnly ? batterySideWingOffset : 0,
                    hoverOffsetY: hoverOffsetY,
                    micMuted: closedMicMuted,
                    usageBars: closedUsageBars
                )
                .opacity(tucksWings ? 0 : 1)
                .scaleEffect(x: tucksWings ? 0.6 : 1, y: tucksWings ? 0.85 : 1, anchor: .center)
                .blur(radius: tucksWings ? 2 : 0)
                .allowsHitTesting(false)
                .transition(.opacity)
                .zIndex(1)
            }

            if showChargingPop && status != .opened {
                ChargingPopView(
                    batteryLevel: batteryManager.batteryLevel,
                    lowBatteryThreshold: settingsManager.lowBatteryThreshold,
                    network: networkStatusManager.glyphState,
                    volume: musicManager.outputVolume,
                    isVolumeMuted: musicManager.isOutputMuted,
                    size: layout.chargingSize,
                    notchWidth: layout.idleWidth
                )
                .offset(y: 1)
                .allowsHitTesting(false)
                .transition(.asymmetric(
                    insertion: .scale(scale: 0.92).combined(with: .opacity),
                    removal: .opacity
                ))
                .zIndex(2)
            }

            if status == .opened {
                ExpandedBatteryView(
                    batteryLevel: batteryManager.batteryLevel,
                    isCharging: batteryManager.isCharging,
                    lowBatteryThreshold: settingsManager.lowBatteryThreshold,
                    network: networkStatusManager.glyphState,
                    volume: musicManager.outputVolume,
                    isVolumeMuted: musicManager.isOutputMuted,
                    size: layout.batteryPanelSize,
                    accessory: micButtonAccessory
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
                        width: layout.batteryPanelSize.width,
                        isShelfDropTargeted: isShelfDropTargeted,
                        meeting: liveActivityModel.activity,
                        onDismissMeeting: {
                            withAnimation(.smooth(duration: 0.3, extraBounce: 0)) {
                                liveActivityModel.dismissMeeting()
                            }
                        }
                    )
                        .offset(y: layout.batteryPanelSize.height + ExtrasPanelView.gapBelowTopSection)
                        .transition(ExtrasPanelView.transition)
                        .zIndex(4)
                }
            }
        }
        .animation(.smooth(duration: 0.22, extraBounce: 0), value: isHovered)
        .animation(animation, value: usesIdleNotchSize)
        .animation(.smooth(duration: 0.4, extraBounce: 0), value: liveActivityModel.activity)
        .onTapGesture {
            // A click opens the notch. Once open, clicks on empty space do nothing; it
            // closes when the pointer leaves, like the music player.
            guard settingsManager.showBattery, status != .opened else { return }

            autoExpandMusicTask?.cancel()

            withAnimation(animation) {
                status = .opened
            }
        }
    }

    func handleBatteryVisibilityChange(_ isEnabled: Bool) {
        dynamicManager.updateCurrentModule()

        guard !isEnabled else { return }

        showChargingPop = false

        guard dynamicManager.currentModule != .music else { return }
        guard status == .opened || status == .popping else { return }

        withAnimation(animation) {
            status = .closed
        }
    }

    func handleMusicVisibilityChange(_ isEnabled: Bool) {
        dynamicManager.updateCurrentModule()

        autoExpandMusicTask?.cancel()
        autoExpandMusicTask = nil
        previewAutoCloseKey = ""
        stagedMusicAutoOpenKey = ""
        showMusicVolumeControl = false

        if focusReturnStatus == .opened || focusReturnStatus == .musicPreview {
            focusReturnStatus = .closed
        }

        if brightnessReturnStatus == .opened || brightnessReturnStatus == .musicPreview {
            brightnessReturnStatus = .closed
        }

        if volumeReturnStatus == .opened || volumeReturnStatus == .musicPreview {
            volumeReturnStatus = .closed
        }

        if agentMusicReturnStatus == .opened || agentMusicReturnStatus == .musicPreview {
            agentMusicReturnStatus = .closed
        }

        if !isEnabled {
            musicStartWidthTask?.cancel()
            musicStartWidthTask = nil
            musicStartUsesIdleWidth = false
            musicEndWidthTask?.cancel()
            musicEndWidthTask = nil

            if status == .opened || status == .musicPreview {
                withAnimation(animation) {
                    status = .closed
                }
            } else {
                beginMusicEndWidthTransitionIfNeeded()
            }

            return
        }

        guard musicManager.hasNowPlayingContent else { return }

        handleNowPlayingContentChange(true)

        guard musicManager.isPlaying else { return }

        handleMusicAutoExpand(isPlaying: true)
    }

    func handleChargingChange(_ newValue: Bool) {
        guard !isAgentAlertBlockingOtherEvents else {
            showChargingPop = false
            return
        }
        guard settingsManager.showBattery else {
            showChargingPop = false
            return
        }
        guard dynamicManager.currentModule == .battery else { return }
        guard hasFinishedInitialAppear else { return }
        guard status == .closed else { return }

        if newValue {
            status = .popping

            withAnimation(.spring(response: 0.38, dampingFraction: 0.84)) {
                showChargingPop = true
            }

            DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) {
                guard !isAgentAlertBlockingOtherEvents else { return }
                guard settingsManager.showBattery else { return }
                guard status != .opened else { return }

                withAnimation(.spring(response: 0.4, dampingFraction: 0.86)) {
                    showChargingPop = false
                }

                DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
                    guard !isAgentAlertBlockingOtherEvents else { return }
                    guard settingsManager.showBattery else { return }
                    withAnimation(animation) {
                        status = .closed
                    }
                }
            }
        } else {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.86)) {
                showChargingPop = false
            }

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
                guard !isAgentAlertBlockingOtherEvents else { return }
                guard settingsManager.showBattery else { return }
                withAnimation(animation) {
                    status = .closed
                }
            }
        }
    }
}
