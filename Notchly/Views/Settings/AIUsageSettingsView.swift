//
//  AIUsageSettingsView.swift
//  Notchly
//
//  The AI Usage settings page: the Usage tab switch, the keys used to read Claude and
//  Codex plan limits, and which copy of claude-usage-monitor is in use.
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
                        subtitle: "Shows Claude 5-hour, weekly and per-model limits, and Codex weekly usage, in the opened notch.",
                        isOn: $settingsManager.showUsageTab
                    )

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
            return "Not found. Build claude-usage-monitor or reinstall Notchly."
        }
        if url.path.hasPrefix(Bundle.main.bundlePath) {
            return "Built in: claude-usage-monitor (Rust), signed and bundled with Notchly."
        }
        return "Using the installed copy at \(url.path)."
    }
}
