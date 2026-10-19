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
    var cameraHousingInset: CGFloat = Self.defaultCameraHousingInset
    var isLowPowerMode = false
    var isChargeOnHold = false
    var chargeHoldStyle: ChargeHoldStyle = .teal

    static let verticalInset: CGFloat = 2.5
    /// How far inside the notch edges macOS reports the camera housing really ends, on
    /// each side. The island's middle keeps the reported width; only the glyphs move in.
    /// Settings > General > Space Beside Camera shifts it.
    static let defaultCameraHousingInset: CGFloat = 3.5
    static let micIconWidth: CGFloat = 14
    static let leftWingSpacing: CGFloat = 8

    /// The wing left of the camera for the usage bars and muted mic; 0 when both are off.
    static func leftWingWidth(
        barCount: Int,
        micMuted: Bool,
        closedHeight: CGFloat,
        cameraHousingInset: CGFloat = defaultCameraHousingInset
    ) -> CGFloat {
        guard barCount > 0 || micMuted else { return 0 }
        let bars = UsageBarsGlyph.width(barCount: barCount)
        let mic = micMuted ? micIconWidth : 0
        let gap = barCount > 0 && micMuted ? leftWingSpacing : 0
        // The same gap on both sides: to the island's edge, and to the camera housing.
        let inset = barsOuterInset(closedHeight: closedHeight)
        return inset + bars + gap + mic + inset - cameraHousingInset
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
    static func wingWidth(closedHeight: CGFloat, cameraHousingInset: CGFloat = defaultCameraHousingInset) -> CGFloat {
        // The same gap on both sides: to the island's edge, and to the camera housing.
        let inset = ringOuterInset(closedHeight: closedHeight)
        return inset + StatusRingGlyph.width(forHeight: glyphHeight(closedHeight: closedHeight)) + inset - cameraHousingInset
    }

    /// The charging pop's wings, one each side: wide enough for "100%" beside the camera,
    /// with the same gaps as the ring.
    static func chargingWingWidth(closedHeight: CGFloat, cameraHousingInset: CGFloat = defaultCameraHousingInset) -> CGFloat {
        let inset = ringOuterInset(closedHeight: closedHeight)
        let text = NSAttributedString(
            string: "100%",
            attributes: [.font: NSFont.monospacedDigitSystemFont(ofSize: ChargingPopView.percentFontSize, weight: .bold)]
        ).size().width.rounded(.up)
        return max(
            wingWidth(closedHeight: closedHeight, cameraHousingInset: cameraHousingInset),
            inset + text + inset - cameraHousingInset
        )
    }

    var body: some View {
        let leftWing = Self.leftWingWidth(
            barCount: usageBars.count,
            micMuted: micMuted,
            closedHeight: size.height,
            cameraHousingInset: cameraHousingInset
        )
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
                height: Self.glyphHeight(closedHeight: size.height),
                isLowPowerMode: isLowPowerMode,
                isChargeOnHold: isChargeOnHold,
                chargeHoldStyle: chargeHoldStyle
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
