//
//  AIUsageSettingsView.swift
//  SupremeNotch
//
//  The AI Usage settings page: the Usage tab switch, how the closed notch's usage bars
//  look, the keys used to read Claude and Codex plan limits, and which copy of
//  claude-usage-monitor is in use.
//

import SwiftUI

struct AIUsageSettingsView: View {
    @ObservedObject var settingsManager: SettingsManager

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            SettingsCard {
                VStack(spacing: 0) {
                    SettingsToggleRow(
                        title: "Usage Tab",
                        subtitle: "Shows Claude 5-hour, weekly and per-model limits, and Codex 5-hour and weekly usage, in the opened notch.",
                        isOn: $settingsManager.showUsageTab
                    )

                    SettingsDivider()

                    UsageBarStylePicker(
                        selection: $settingsManager.usageBarStyle,
                        resetStyle: settingsManager.usageResetStyle
                    )
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .disabled(!settingsManager.showUsageTab)
                    .opacity(settingsManager.showUsageTab ? 1 : 0.45)

                    SettingsDivider()

                    UsageResetStylePicker(
                        selection: $settingsManager.usageResetStyle,
                        barStyle: settingsManager.usageBarStyle
                    )
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .disabled(!settingsManager.showUsageTab)
                    .opacity(settingsManager.showUsageTab ? 1 : 0.45)

                    SettingsDivider()

                    UsageBarChoices(settingsManager: settingsManager)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 12)
                        .disabled(!settingsManager.showUsageTab)
                        .opacity(settingsManager.showUsageTab ? 1 : 0.45)

                    SettingsDivider()

                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Usage Monitor")
                                .font(.system(size: 13, weight: .semibold))
                            Text(monitorDescription)
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        }
                        Spacer()
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                }
            }

            SettingsCard {
                UsageCredentialsView()
                    .disabled(!settingsManager.showUsageTab)
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private var monitorDescription: String {
        guard let url = AIUsageMonitor.binaryURL() else {
            return "Not found. Build claude-usage-monitor or reinstall SupremeNotch."
        }
        if url.path.hasPrefix(Bundle.main.bundlePath) {
            return "Built in: claude-usage-monitor (Rust), signed and bundled with SupremeNotch."
        }
        return "Using the installed copy at \(url.path)."
    }
}

/// Chooses how the closed notch's usage bars are drawn, with a live preview of each.
private struct UsageBarStylePicker: View {
    @Binding var selection: UsageBarStyle
    let resetStyle: UsageResetStyle

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Usage Bars")
                    .font(.system(size: 13, weight: .medium))
                Text("The colored part of each bar beside the camera is what's left. A bar at its limit turns purple.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 10) {
                ForEach(UsageBarStyle.allCases) { style in
                    option(style)
                }
            }
        }
    }

    private func option(_ style: UsageBarStyle) -> some View {
        UsageBarOption(
            title: style.title,
            subtitle: style.subtitle,
            isSelected: selection == style,
            preview: UsageBarsGlyph(bars: UsageBar.settingsSample, height: 26, style: style, resetStyle: resetStyle)
        ) {
            selection = style
        }
    }
}

/// Chooses how each usage bar shows the time until its limit resets.
private struct UsageResetStylePicker: View {
    @Binding var selection: UsageResetStyle
    let barStyle: UsageBarStyle

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Time Until Reset")
                    .font(.system(size: 13, weight: .medium))
                Text("How each bar shows how far its 5-hour or weekly window has run.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 10) {
                ForEach(UsageResetStyle.allCases) { style in
                    UsageBarOption(
                        title: style.title,
                        subtitle: style.subtitle,
                        isSelected: selection == style,
                        preview: UsageBarsGlyph(bars: UsageBar.settingsSample, height: 26, style: barStyle, resetStyle: style)
                    ) {
                        selection = style
                    }
                }
            }
        }
    }
}

/// One choice in a usage bar picker: a preview on black, its name, and a check when chosen.
private struct UsageBarOption<Preview: View>: View {
    let title: String
    let subtitle: String
    let isSelected: Bool
    let preview: Preview
    let choose: () -> Void

    var body: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.16)) { choose() }
        } label: {
            HStack(spacing: 10) {
                preview
                    .frame(width: 46, height: 42)
                    .background(Color.black, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(isSelected ? Color.accentColor.opacity(0.62) : Color.white.opacity(0.08), lineWidth: 1)
                    }

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.primary)
                    Text(subtitle)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
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
        .accessibilityLabel(title)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

private extension UsageBar {
    /// Three Claude limits at different levels and paces, and Codex at its limit.
    static let settingsSample = [
        UsageBar(id: "5 hours", percent: 15, scale: .claude, elapsed: 0.4),
        UsageBar(id: "Week", percent: 40, scale: .claude, elapsed: 0.6),
        UsageBar(id: "Model", percent: 70, scale: .claude, elapsed: 0.55),
        UsageBar(id: "Codex", percent: 100, scale: .codex, elapsed: 0.8)
    ]
}

/// Which limits get a bar beside the camera. The Usage tab always lists them all.
private struct UsageBarChoices: View {
    @ObservedObject var settingsManager: SettingsManager

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Bars Beside the Camera")
                    .font(.system(size: 13, weight: .medium))
                Text("Choose which limits get a bar in the closed notch. The Usage tab still shows them all.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }

            // Claude's limits on one row, Codex's on the next.
            VStack(alignment: .leading, spacing: 8) {
                ForEach([false, true], id: \.self) { codex in
                    HStack(spacing: 18) {
                        ForEach(UsageLimitKind.allCases.filter { $0.isCodex == codex }) { kind in
                            Toggle(kind.title, isOn: Binding(
                                get: { settingsManager.showsUsageBar(kind) },
                                set: { settingsManager.setShowsUsageBar(kind, $0) }
                            ))
                            .toggleStyle(.checkbox)
                            .font(.system(size: 12, weight: .medium))
                            .help(Text(Self.help(for: kind)))
                        }
                        Spacer(minLength: 0)
                    }
                }
            }
        }
    }

    private static func help(for kind: UsageLimitKind) -> String {
        switch kind {
        case .fiveHour: return "Claude's 5-hour session limit"
        case .weekly: return "Claude's weekly limit across all models"
        case .modelWeekly: return "Claude's weekly limit for Fable"
        case .codexFiveHour: return "Codex's 5-hour limit, on plans that have one"
        case .codexWeekly: return "Codex's weekly limit"
        }
    }
}
