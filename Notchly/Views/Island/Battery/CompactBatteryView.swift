//
//  CompactBatteryView.swift
//  Notchly
//
//  Created by n0xbyte on 25.03.2026.
//

import SwiftUI

/// The closed battery island: the status ring sits right of the camera notch. A left
/// wing opens only for the usage bars and the muted mic.
struct CompactBatteryView: View {
    let batteryLevel: Int
    let isCharging: Bool
    let lowBatteryThreshold: Int
    let network: GlyphNetworkState
    let volume: Double?
    let isVolumeMuted: Bool
    let size: CGSize
    /// How far the island's center sits right of the canvas center.
    let horizontalOffset: CGFloat
    let hoverOffsetY: CGFloat
    var micMuted = false
    var usageBars: [UsageBar] = []
    var usageBarStyle: UsageBarStyle = .colorHangs

    static let verticalInset: CGFloat = 2.5
    /// Space between a glyph and the camera notch.
    static let horizontalInset: CGFloat = 11
    static let micIconWidth: CGFloat = 14
    static let leftWingSpacing: CGFloat = 8

    /// The wing left of the camera for the usage bars and muted mic; 0 when both are off.
    static func leftWingWidth(barCount: Int, micMuted: Bool, closedHeight: CGFloat) -> CGFloat {
        guard barCount > 0 || micMuted else { return 0 }
        let bars = UsageBarsGlyph.width(barCount: barCount)
        let mic = micMuted ? micIconWidth : 0
        let gap = barCount > 0 && micMuted ? leftWingSpacing : 0
        return horizontalInset + bars + gap + mic + barsOuterInset(closedHeight: closedHeight)
    }

    static func glyphHeight(closedHeight: CGFloat) -> CGFloat {
        (closedHeight - verticalInset * 2) * 0.95
    }

    static func barsHeight(closedHeight: CGFloat) -> CGFloat {
        glyphHeight(closedHeight: closedHeight) - 3
    }

    /// The ring sits as far from the island's right edge as from its bottom edge.
    static func ringOuterInset(closedHeight: CGFloat) -> CGFloat {
        (closedHeight - glyphHeight(closedHeight: closedHeight)) / 2
    }

    /// The bars sit as far from the island's left edge as from its bottom edge.
    static func barsOuterInset(closedHeight: CGFloat) -> CGFloat {
        (closedHeight - barsHeight(closedHeight: closedHeight)) / 2
    }

    /// The wing right of the notch that holds the glyph.
    static func wingWidth(closedHeight: CGFloat) -> CGFloat {
        horizontalInset + StatusRingGlyph.width(forHeight: glyphHeight(closedHeight: closedHeight))
            + ringOuterInset(closedHeight: closedHeight)
    }

    var body: some View {
        let leftWing = Self.leftWingWidth(barCount: usageBars.count, micMuted: micMuted, closedHeight: size.height)
        HStack(spacing: 0) {
            if leftWing > 0 {
                HStack(spacing: Self.leftWingSpacing) {
                    if !usageBars.isEmpty {
                        UsageBarsGlyph(
                            bars: usageBars,
                            height: Self.barsHeight(closedHeight: size.height),
                            style: usageBarStyle
                        )
                    }
                    if micMuted {
                        MutedMicIndicator()
                            .frame(width: Self.micIconWidth)
                            .transition(.opacity.combined(with: .scale(scale: 0.6)))
                    }
                }
                .padding(.leading, Self.barsOuterInset(closedHeight: size.height))
                .frame(width: leftWing, alignment: .leading)
                .transition(.opacity)
            }

            Spacer(minLength: 0)

            StatusRingGlyph(
                batteryLevel: batteryLevel,
                isCharging: isCharging,
                lowBatteryThreshold: lowBatteryThreshold,
                network: network,
                volume: volume,
                isMuted: isVolumeMuted,
                height: Self.glyphHeight(closedHeight: size.height)
            )
        }
        .padding(.trailing, Self.ringOuterInset(closedHeight: size.height))
        .frame(width: size.width, height: size.height)
        .offset(x: horizontalOffset, y: hoverOffsetY)
        .animation(.smooth(duration: 0.25, extraBounce: 0), value: micMuted)
        .animation(.smooth(duration: 0.25, extraBounce: 0), value: usageBars.count)
    }
}

/// A small red slashed mic in the closed wings while the microphone is muted.
struct MutedMicIndicator: View {
    var body: some View {
        Image(systemName: "mic.slash.fill")
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(Color(red: 0.97, green: 0.32, blue: 0.29))
            .help(Text("Microphone muted"))
    }
}
