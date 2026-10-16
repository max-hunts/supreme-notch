//
//  ChargingPopView.swift
//  Notchly
//
//  Created by n0xbyte on 25.03.2026.
//

import SwiftUI

/// Shown briefly when power is connected. The island opens on both sides of the camera:
/// the percentage on the left, and the status ring, now green, where it always sits.
struct ChargingPopView: View {
    let batteryLevel: Int
    let lowBatteryThreshold: Int
    let network: GlyphNetworkState
    let volume: Double?
    let isVolumeMuted: Bool
    let size: CGSize
    let notchWidth: CGFloat

    var body: some View {
        let wing = max(0, (size.width - notchWidth) / 2)
        HStack(spacing: 0) {
            Text("\(batteryLevel)%")
                .font(.system(size: 14, weight: .bold).monospacedDigit())
                .foregroundStyle(Color(nsColor: .systemGreen))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .frame(width: wing)

            Spacer(minLength: notchWidth)

            HStack(spacing: 0) {
                Spacer(minLength: 0)
                StatusRingGlyph(
                    batteryLevel: batteryLevel,
                    isCharging: true,
                    lowBatteryThreshold: lowBatteryThreshold,
                    network: network,
                    volume: volume,
                    isMuted: isVolumeMuted,
                    height: CompactBatteryView.glyphHeight(closedHeight: size.height)
                )
            }
            .padding(.trailing, CompactBatteryView.ringOuterInset(closedHeight: size.height))
            .frame(width: wing)
        }
        .frame(width: size.width, height: size.height)
    }
}
