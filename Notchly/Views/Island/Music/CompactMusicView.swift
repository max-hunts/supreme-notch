//
//  CompactMusicView.swift
//  Notchly
//
//  Created by n0xbyte on 25.03.2026.
//

import SwiftUI
import AppKit

/// The closed music island. The artwork sits in a wing left of the camera, placed like the
/// usage bars, and the status ring sits right of it, as when no music plays. With the
/// battery turned off the waveform takes the ring's place.
struct CompactMusicView: View {
    let artwork: NSImage?
    let waveformColor: Color
    let isPlaying: Bool
    let size: CGSize
    let hoverOffsetY: CGFloat
    let skipIndicator: String?
    /// Shown in place of the waveform while an agent works or a meeting is near.
    var liveActivity: LiveActivity? = nil
    var micMuted = false
    /// The ring right of the camera; nil shows the waveform there instead.
    var statusRing: StatusRingGlyph? = nil
    /// How far the island's center sits right of the canvas center.
    var horizontalOffset: CGFloat = 0

    static let artworkCornerRadius: CGFloat = 4
    static let waveformWidth: CGFloat = 36

    /// The wing left of the camera: the artwork, and the muted mic beside it.
    static func leftWingWidth(
        micMuted: Bool,
        closedHeight: CGFloat,
        cameraHousingInset: CGFloat = CompactBatteryView.defaultCameraHousingInset
    ) -> CGFloat {
        let inset = CompactBatteryView.barsOuterInset(closedHeight: closedHeight)
        let artwork = CompactBatteryView.barsHeight(closedHeight: closedHeight)
        let mic = micMuted ? CompactBatteryView.leftWingSpacing + CompactBatteryView.micIconWidth : 0
        return inset + artwork + mic + inset - cameraHousingInset
    }

    /// The wing right of the camera when it holds the waveform instead of the ring.
    static func waveformWingWidth(
        closedHeight: CGFloat,
        cameraHousingInset: CGFloat = CompactBatteryView.defaultCameraHousingInset
    ) -> CGFloat {
        let inset = CompactBatteryView.ringOuterInset(closedHeight: closedHeight)
        return inset + waveformWidth + inset - cameraHousingInset
    }

    var body: some View {
        if let liveActivity {
            liveActivityBody(liveActivity)
        } else {
            wingsBody
        }
    }

    private var wingsBody: some View {
        let artworkSize = CompactBatteryView.barsHeight(closedHeight: size.height)
        return HStack(spacing: 0) {
            HStack(spacing: CompactBatteryView.leftWingSpacing) {
                artworkView(size: artworkSize)
                if micMuted {
                    MutedMicIndicator()
                        .frame(width: CompactBatteryView.micIconWidth)
                        .transition(.opacity.combined(with: .scale(scale: 0.6)))
                }
            }
            .padding(.leading, CompactBatteryView.barsOuterInset(closedHeight: size.height))

            Spacer(minLength: 0)

            if let statusRing {
                ZStack {
                    statusRing
                        .opacity(skipIndicator == nil ? 1 : 0.18)
                        .scaleEffect(skipIndicator == nil ? 1 : 0.9)
                    if let skipIndicator {
                        Image(systemName: skipIndicator)
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(.white)
                            .transition(.opacity.combined(with: .scale(scale: 0.9)))
                    }
                }
                .animation(.easeInOut(duration: 0.18), value: skipIndicator)
            } else {
                MusicWaveformView(isPlaying: isPlaying, color: waveformColor, skipIndicator: skipIndicator)
                    .frame(width: Self.waveformWidth, height: 18)
            }
        }
        .padding(.trailing, CompactBatteryView.ringOuterInset(closedHeight: size.height))
        .frame(width: size.width, height: size.height)
        .offset(x: horizontalOffset, y: hoverOffsetY)
        .animation(.smooth(duration: 0.25, extraBounce: 0), value: micMuted)
    }

    private func liveActivityBody(_ liveActivity: LiveActivity) -> some View {
        HStack(spacing: 10) {
            artworkView(size: 22)

            Spacer()

            if micMuted {
                MutedMicIndicator()
                    .transition(.opacity)
            }

            LiveActivityBadge(activity: liveActivity)
                .transition(.opacity)
        }
        .padding(.horizontal, 12)
        .frame(width: size.width, height: size.height)
        .offset(y: hoverOffsetY)
    }

    @ViewBuilder
    private func artworkView(size: CGFloat) -> some View {
        if let artwork {
            Image(nsImage: artwork)
                .resizable()
                .scaledToFill()
                .frame(width: size, height: size)
                .clipShape(RoundedRectangle(cornerRadius: Self.artworkCornerRadius, style: .continuous))
        } else {
            Image(systemName: "music.note")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: size, height: size)
        }
    }
}
