//
//  BatterySettingsView.swift
//  Notchly
//
//  Created by n0xbyte on 01.04.2026.
//

import SwiftUI

struct BatterySettingsView: View {
    @ObservedObject var settingsManager: SettingsManager

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            SettingsCard {
                VStack(spacing: 0) {
                    SettingsToggleRow(
                        title: "Show Battery Island",
                        subtitle: "Display battery state and charging updates around the notch.",
                        isOn: $settingsManager.showBattery
                    )

                    SettingsDivider()

                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            VStack(alignment: .leading, spacing: 3) {
                                Text("Low Battery Threshold")
                                    .font(.system(size: 13, weight: .medium))

                                Text("Choose when BetterNotch should show the low battery state.")
                                    .font(.system(size: 12))
                                    .foregroundStyle(.secondary)
                            }

                            Spacer()

                            Text("\(settingsManager.lowBatteryThreshold)%")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }

                        Slider(
                            value: Binding(
                                get: { Double(settingsManager.lowBatteryThreshold) },
                                set: { settingsManager.lowBatteryThreshold = Int($0) }
                            ),
                            in: 5...50,
                            step: 5
                        )
                        .disabled(!settingsManager.showBattery)
                        .opacity(settingsManager.showBattery ? 1 : 0.45)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)

                    SettingsDivider()

                    ChargeHoldStylePicker(selection: $settingsManager.chargeHoldStyle)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 12)
                        .disabled(!settingsManager.showBattery)
                        .opacity(settingsManager.showBattery ? 1 : 0.45)
                }
            }

            Text("Controls when the low battery state appears while Battery Island is enabled.")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 4)
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }
}

/// Chooses how the status ring looks while macOS holds the charge, with a live preview.
private struct ChargeHoldStylePicker: View {
    @Binding var selection: ChargeHoldStyle

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Charging On Hold")
                    .font(.system(size: 13, weight: .medium))
                Text("How the ring looks when macOS pauses charging to protect the battery, such as with Optimized Battery Charging.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }

            LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                ForEach(ChargeHoldStyle.allCases) { style in
                    option(style)
                }
            }
        }
    }

    private func option(_ style: ChargeHoldStyle) -> some View {
        let isSelected = selection == style
        return Button {
            withAnimation(.easeInOut(duration: 0.16)) { selection = style }
        } label: {
            HStack(spacing: 10) {
                StatusRingGlyph(
                    batteryLevel: 84,
                    isCharging: true,
                    lowBatteryThreshold: 20,
                    network: .wifi(.strong),
                    volume: 0.6,
                    isMuted: false,
                    height: 28,
                    isChargeOnHold: true,
                    chargeHoldStyle: style
                )
                .frame(width: 46, height: 42)
                .background(Color.black, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(isSelected ? Color.accentColor.opacity(0.62) : Color.white.opacity(0.08), lineWidth: 1)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(style.title)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.primary)
                    Text(style.subtitle)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 0)

                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.white, Color.accentColor)
                }
            }
            .padding(.horizontal, 10)
            .frame(height: 58)
            .frame(maxWidth: .infinity)
            .background(isSelected ? Color.accentColor.opacity(0.18) : Color.black.opacity(0.12))
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(isSelected ? Color.accentColor.opacity(0.5) : Color.white.opacity(0.08), lineWidth: 1)
            }
            .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(SubtleHoverButtonStyle(
            pressedScale: 0.97,
            hoverScale: 1.012,
            hoverBackgroundOpacity: 0.06,
            cornerRadius: 10
        ))
        .accessibilityLabel(style.title)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
