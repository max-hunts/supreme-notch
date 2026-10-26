//
//  ExpandedBatteryView.swift
//  SupremeNotch
//
//  Created by n0xbyte on 25.03.2026.
//

import SwiftUI

/// The opened battery panel: one large status ring, centered, with the percentage under
/// it. Green already says charging, so there is no bar or state text.
struct ExpandedBatteryView: View {
    let batteryLevel: Int
    let isCharging: Bool
    let lowBatteryThreshold: Int
    let network: GlyphNetworkState
    let volume: Double?
    let isVolumeMuted: Bool
    let size: CGSize
    /// A control at the right edge, such as the mic button.
    var accessory: AnyView? = nil
    var isLowPowerMode = false
    var isChargeOnHold = false
    var chargeHoldStyle: ChargeHoldStyle = .teal
    /// False when the battery is turned off; the mic button stays.
    var showsRing = true

    private var showsOnHold: Bool { isCharging && isChargeOnHold && batteryLevel < 100 }

    private var labelColor: Color {
        if showsOnHold && chargeHoldStyle == .teal { return ChargeHoldStyle.tealColor }
        return StatusRingGlyph.stateColor(
            isCharging: isCharging,
            batteryLevel: batteryLevel,
            lowBatteryThreshold: lowBatteryThreshold,
            isLowPowerMode: isLowPowerMode
        ) ?? .white.opacity(0.7)
    }

    var body: some View {
        VStack(spacing: 5) {
            if showsRing {
                StatusRingGlyph(
                    batteryLevel: batteryLevel,
                    isCharging: isCharging,
                    lowBatteryThreshold: lowBatteryThreshold,
                    network: network,
                    volume: volume,
                    isMuted: isVolumeMuted,
                    height: 58,
                    isLowPowerMode: isLowPowerMode,
                    isChargeOnHold: isChargeOnHold,
                    chargeHoldStyle: chargeHoldStyle
                )

                // The percentage takes the ring's color when it has one.
                Text(showsOnHold ? "\(batteryLevel)% · On hold" : "\(batteryLevel)%")
                    .font(.system(size: 12, weight: .semibold).monospacedDigit())
                    .foregroundStyle(labelColor)
            }
        }
        .frame(maxWidth: .infinity)
        .overlay(alignment: .trailing) {
            if let accessory {
                accessory
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 18)
        .frame(width: size.width, height: size.height, alignment: .top)
        .foregroundStyle(.white)
    }
}
