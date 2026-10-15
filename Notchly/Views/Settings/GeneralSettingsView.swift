//
//  GeneralSettingsView.swift
//  Notchly
//
//  Created by n0xbyte on 01.04.2026.
//

import SwiftUI

struct GeneralSettingsView: View {
    @ObservedObject var settingsManager: SettingsManager
    @ObservedObject var lockScreenIdentityManager: LockScreenIdentityManager

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            SettingsCard {
                VStack(spacing: 0) {
                    DisplayTargetPicker(
                        selection: $settingsManager.displayTarget
                    )

                    SettingsDivider()

                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            VStack(alignment: .leading, spacing: 3) {
                                Text("Island Width")
                                    .font(.system(size: 13, weight: .medium))

                                Text("Set the base width used by the dynamic island.")
                                    .font(.system(size: 12))
                                    .foregroundStyle(.secondary)
                            }

                            Spacer()

                            Text("\(Int(settingsManager.islandWidth))px")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }

                        Slider(
                            value: $settingsManager.islandWidth,
                            in: 280...360,
                            step: 2
                        )
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)

                    SettingsDivider()

                    SettingsToggleRow(
                        title: "Launch at Login",
                        subtitle: "Open Notchly automatically when you sign in.",
                        isOn: $settingsManager.launchAtLogin
                    )

                    SettingsDivider()

                    LockScreenProfileSettingsRow(
                        manager: lockScreenIdentityManager
                    )

                    SettingsDivider()

                    SettingsToggleRow(
                        title: "Hide in Fullscreen",
                        subtitle: "Hide the island while the active app is fullscreen.",
                        isOn: $settingsManager.hideNotchWhenFullscreen
                    )

                    SettingsDivider()

                    SettingsToggleRow(
                        title: "Network Status",
                        subtitle: "Show Wi-Fi, Personal Hotspot, and internet availability changes.",
                        isOn: $settingsManager.showNetworkStatus
                    )

                    SettingsDivider()

                    UnlockSoundSettingsRow(
                        isEnabled: $settingsManager.enableLockSound
                    )
                }
            }
        }
        .onAppear {
            lockScreenIdentityManager.refreshAuthorizationState()
        }
        .onReceive(NotificationCenter.default.publisher(
            for: NSApplication.didBecomeActiveNotification
        )) { _ in
            lockScreenIdentityManager.refreshAuthorizationState()
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }
}

private struct LockScreenProfileSettingsRow: View {
    @ObservedObject var manager: LockScreenIdentityManager

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Hide Lock Screen Profile")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.primary)

                Text(description)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            Spacer(minLength: 16)

            if manager.authorizationState == .enabled {
                Label("Enabled", systemImage: "checkmark.circle.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.green)
            } else {
                Button(actionTitle) {
                    manager.requestAuthorizationFromSettings()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(manager.authorizationState == .unavailable)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity)
    }

    private var description: String {
        switch manager.authorizationState {
        case .enabled:
            return "Your photo and name are hidden while expanded artwork is visible."
        case .needsApproval:
            return "Allow Notchly in Login Items to hide your profile during expanded artwork."
        case .disabled:
            return "Enable the background helper used only while expanded artwork is visible."
        case .unavailable:
            return "Move Notchly to Applications before enabling the Lock Screen helper."
        }
    }

    private var actionTitle: String {
        manager.authorizationState == .needsApproval
            ? "Open Settings"
            : "Enable"
    }
}

private struct UnlockSoundSettingsRow: View {
    @Binding var isEnabled: Bool

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text("Unlock Sound")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.primary)

                    Button {
                        UnlockSoundPlayer.shared.play(bypassThrottle: true)
                    } label: {
                        Image(systemName: "play.fill")
                            .font(.system(size: 7, weight: .bold))
                            .foregroundStyle(.white.opacity(0.78))
                            .frame(width: 18, height: 18)
                            .background(.white.opacity(0.12))
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Preview Unlock Sound")
                }

                Text("Play a subtle sound when your Mac unlocks.")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            Spacer(minLength: 16)

            Toggle("", isOn: $isEnabled)
                .toggleStyle(.switch)
                .labelsHidden()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity)
    }
}

struct CodexSettingsView: View {
    @ObservedObject var settingsManager: SettingsManager
    @ObservedObject var codexHookIntegrationManager: CodexHookIntegrationManager
    @ObservedObject var claudeHookIntegrationManager: ClaudeHookIntegrationManager
    @ObservedObject var cursorHookIntegrationManager: CursorHookIntegrationManager

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            SettingsCard {
                VStack(spacing: 0) {
                    AgentHookIntegrationRow(
                        title: "Codex Alerts",
                        manager: codexHookIntegrationManager,
                        description: "Shows Codex approval and completion alerts using transparent local hooks."
                    )

                    SettingsDivider()

                    AgentHookIntegrationRow(
                        title: "Claude Code Alerts",
                        manager: claudeHookIntegrationManager,
                        description: "Shows approval, waiting, completion, and failure alerts from Claude Code terminal sessions."
                    )

                    SettingsDivider()

                    AgentHookIntegrationRow(
                        title: "Cursor Alerts",
                        manager: cursorHookIntegrationManager,
                        description: "Shows Cursor shell approval and completion alerts using local Cursor hooks."
                    )

                    SettingsDivider()

                    CodexAlertSoundSettingsRow(
                        title: "Need Approval Sound",
                        subtitle: "Play a subtle sound when an AI agent is waiting for approval.",
                        kind: .accessRequest,
                        isEnabled: $settingsManager.enableCodexApprovalAlertSound
                    )

                    SettingsDivider()

                    CodexAlertSoundSettingsRow(
                        title: "Task Completed Sound",
                        subtitle: "Play a subtle sound when an AI agent finishes a task.",
                        kind: .completed,
                        isEnabled: $settingsManager.enableCodexCompletedAlertSound
                    )

                    SettingsDivider()

                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            VStack(alignment: .leading, spacing: 3) {
                                Text("Job Done Duration")
                                    .font(.system(size: 13, weight: .medium))

                                Text("How long AI agent completion alerts stay visible before returning to music.")
                                    .font(.system(size: 12))
                                    .foregroundStyle(.secondary)
                            }

                            Spacer()

                            Text(String(format: "%.1fs", settingsManager.codexCompletedAlertDuration))
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }

                        Slider(
                            value: $settingsManager.codexCompletedAlertDuration,
                            in: 1.5...6.0,
                            step: 0.1
                        )
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                }
            }

            SettingsCard {
                VStack(spacing: 0) {
                    SettingsToggleRow(
                        title: "Approve from the Notch",
                        subtitle: "Show what the agent wants to run with Approve, Deny, and Terminal buttons.",
                        isOn: $settingsManager.approveFromNotch
                    )

                    SettingsDivider()

                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            VStack(alignment: .leading, spacing: 3) {
                                Text("Wait for a Decision")
                                    .font(.system(size: 13, weight: .medium))

                                Text("After this, the agent falls back to its own prompt.")
                                    .font(.system(size: 12))
                                    .foregroundStyle(.secondary)
                            }

                            Spacer()

                            Text("\(Int(settingsManager.approvalWaitSeconds))s")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }

                        Slider(
                            value: $settingsManager.approvalWaitSeconds,
                            in: 10...120,
                            step: 5
                        )
                        .disabled(!settingsManager.approveFromNotch)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)

                    SettingsDivider()

                    SettingsToggleRow(
                        title: "Completion Summary",
                        subtitle: "Show the first line of the agent's final message when a task finishes.",
                        isOn: $settingsManager.showCompletionSummary
                    )
                }
            }
        }
        .onAppear {
            codexHookIntegrationManager.refreshStatus()
            claudeHookIntegrationManager.refreshStatus()
            cursorHookIntegrationManager.refreshStatus()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            codexHookIntegrationManager.refreshStatus()
            claudeHookIntegrationManager.refreshStatus()
            cursorHookIntegrationManager.refreshStatus()
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }
}

private struct CodexAlertSoundSettingsRow: View {
    let title: String
    let subtitle: String
    let kind: AgentEventKind
    @Binding var isEnabled: Bool

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(title)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.primary)

                    previewButton(
                        kind: kind,
                        accessibilityLabel: "Preview \(title)"
                    )
                }

                Text(subtitle)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            Spacer(minLength: 16)

            Toggle("", isOn: $isEnabled)
                .toggleStyle(.switch)
                .labelsHidden()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity)
    }

    private func previewButton(
        kind: AgentEventKind,
        accessibilityLabel: String
    ) -> some View {
        Button {
            CodexAlertSoundPlayer.shared.play(for: kind, bypassThrottle: true)
        } label: {
            Image(systemName: "play.fill")
                .font(.system(size: 7, weight: .bold))
                .foregroundStyle(.white.opacity(0.78))
                .frame(width: 18, height: 18)
                .background(.white.opacity(0.12))
                .clipShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
    }
}

private protocol AgentHookIntegrationManaging: ObservableObject {
    var installState: AgentHookInstallState { get }
    var isInstalled: Bool { get }
    var configPreview: String { get }
    func refreshStatus()
    func install()
}

extension CodexHookIntegrationManager: AgentHookIntegrationManaging {}
extension ClaudeHookIntegrationManager: AgentHookIntegrationManaging {}
extension CursorHookIntegrationManager: AgentHookIntegrationManaging {}

private struct AgentHookIntegrationRow<Manager: AgentHookIntegrationManaging>: View {
    let title: String
    @ObservedObject var manager: Manager
    let description: String
    @State private var isPreviewVisible = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 8) {
                        Text(title)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.primary)

                        Text(statusText)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(statusColor)
                            .padding(.horizontal, 8)
                            .frame(height: 22)
                            .background(statusColor.opacity(0.16))
                            .clipShape(Capsule())
                    }

                    Text(descriptionText)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                Spacer(minLength: 16)

                Button {
                    isPreviewVisible.toggle()
                } label: {
                    Text(isPreviewVisible ? "Hide Details" : "Show Details")
                        .font(.system(size: 12, weight: .semibold))
                        .padding(.horizontal, 12)
                        .frame(height: 32)
                        .background(Color.white.opacity(0.08))
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
                .buttonStyle(SubtleHoverButtonStyle(
                    pressedScale: 0.96,
                    hoverScale: 1.025,
                    hoverBackgroundOpacity: 0.08,
                    cornerRadius: 16
                ))

                Button {
                    manager.install()
                } label: {
                    Text(installButtonTitle)
                        .font(.system(size: 12, weight: .semibold))
                        .padding(.horizontal, 14)
                        .frame(height: 32)
                        .background(manager.isInstalled ? Color.white.opacity(0.08) : Color.accentColor.opacity(0.26))
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
                .buttonStyle(SubtleHoverButtonStyle(
                    pressedScale: 0.96,
                    hoverScale: 1.025,
                    hoverBackgroundOpacity: 0.08,
                    cornerRadius: 16
                ))
            }

            if isPreviewVisible {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Hooks run locally and nothing leaves this Mac. For approvals Notchly reads the requested tool and its input to show a summary. For completion summaries it reads the agent's final message from the local transcript.")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    Text(manager.configPreview)
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundStyle(.primary.opacity(0.82))
                        .textSelection(.enabled)
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.black.opacity(0.22))
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .stroke(Color.white.opacity(0.08), lineWidth: 1)
                        }
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity)
    }

    private var statusText: String {
        switch manager.installState {
        case .unknown:
            return "Checking"
        case .installing:
            return "Installing"
        case .installed:
            return "Enabled"
        case .notInstalled:
            return "Not configured"
        case .failed:
            return "Failed"
        }
    }

    private var statusColor: Color {
        switch manager.installState {
        case .installed:
            return .green
        case .failed:
            return .red
        case .unknown, .installing:
            return .secondary
        case .notInstalled:
            return .orange
        }
    }

    private var descriptionText: String {
        if case let .failed(message) = manager.installState {
            return message
        }

        return description
    }

    private var installButtonTitle: String {
        switch manager.installState {
        case .installing:
            return "Installing..."
        case .installed:
            return "Reinstall"
        default:
            return "Install Hook"
        }
    }
}

private struct DisplayTargetPicker: View {
    @Binding var selection: DisplayTarget

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Display")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.primary)

                Text("Choose where Notchly appears.")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 10) {
                ForEach(DisplayTarget.allCases, id: \.self) { target in
                    DisplayTargetOption(
                        target: target,
                        isSelected: selection == target
                    ) {
                        withAnimation(.easeInOut(duration: 0.16)) {
                            selection = target
                        }
                    }
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct DisplayTargetOption: View {
    let target: DisplayTarget
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                ZStack(alignment: .topTrailing) {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(isSelected ? Color.accentColor.opacity(0.28) : Color.white.opacity(0.08))
                        .frame(width: 54, height: 42)
                        .overlay {
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .stroke(isSelected ? Color.accentColor.opacity(0.62) : Color.white.opacity(0.08), lineWidth: 1)
                        }

                    Image(systemName: target.symbolName)
                        .font(.system(size: 22, weight: .medium))
                        .foregroundStyle(isSelected ? .white : .secondary)
                        .frame(width: 54, height: 42)

                    if isSelected {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.white, Color.accentColor)
                            .offset(x: 4, y: -4)
                    }
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(target.title)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.primary)

                    Text(target.subtitle)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.9)
                }

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10)
            .frame(height: 62)
            .frame(maxWidth: .infinity)
            .background(isSelected ? Color.accentColor.opacity(0.18) : Color.black.opacity(0.12))
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(isSelected ? Color.accentColor.opacity(0.5) : Color.white.opacity(0.08), lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
    }
}


struct GlancesSettingsView: View {
    @ObservedObject var settingsManager: SettingsManager

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            SettingsCard {
                VStack(spacing: 0) {
                    SettingsToggleRow(
                        title: "Download Finished",
                        subtitle: "Shows the file name when a download lands in Downloads. Click to reveal it in Finder.",
                        isOn: $settingsManager.showDownloadGlance
                    )

                    SettingsDivider()

                    SettingsToggleRow(
                        title: "Download Progress",
                        subtitle: "Shows a live ring while a large download runs. Click the island to hide it.",
                        isOn: $settingsManager.showDownloadProgress
                    )

                    SettingsDivider()

                    SettingsToggleRow(
                        title: "AirPods Battery",
                        subtitle: "Shows left, right, and case battery when Bluetooth headphones connect.",
                        isOn: $settingsManager.showAirPodsGlance
                    )

                    SettingsDivider()

                    SettingsToggleRow(
                        title: "Low Accessory Battery",
                        subtitle: "Warns when AirPods, a mouse, or a keyboard runs low.",
                        isOn: $settingsManager.showAccessoryBatteryWarning
                    )

                    SettingsDivider()

                    SettingsToggleRow(
                        title: "External Drives",
                        subtitle: "Shows a drive when it connects. Click to eject, then see when it is safe to remove.",
                        isOn: $settingsManager.showDriveGlance
                    )

                    SettingsDivider()

                    SettingsToggleRow(
                        title: "Low Disk Space",
                        subtitle: "Warns once when the startup disk drops below 10% free.",
                        isOn: $settingsManager.showLowDiskWarning
                    )

                    SettingsDivider()

                    SettingsToggleRow(
                        title: "Open on Hover",
                        subtitle: "Rest the pointer on the notch to open it, no click needed.",
                        isOn: $settingsManager.openOnHover
                    )

                    SettingsDivider()

                    SettingsToggleRow(
                        title: "Listening Ports",
                        subtitle: "A Ports tab in the opened notch lists your local servers.",
                        isOn: $settingsManager.showPortsPanel
                    )

                    SettingsDivider()

                    SettingsToggleRow(
                        title: "Agent Sessions",
                        subtitle: "An Agents tab shows each Claude Code and Codex session and what it is doing.",
                        isOn: $settingsManager.showAgentSessions
                    )

                    SettingsDivider()

                    SettingsToggleRow(
                        title: "System Stats",
                        subtitle: "A System tab shows CPU, memory and disk use, and network traffic over the last five minutes.",
                        isOn: $settingsManager.showSystemTab
                    )

                    SettingsDivider()

                    SettingsToggleRow(
                        title: "File Shelf",
                        subtitle: "Drag files onto the notch to park them, then drag them out into any app.",
                        isOn: $settingsManager.showFileShelf
                    )

                    SettingsDivider()

                    SettingsToggleRow(
                        title: "Mic Mute",
                        subtitle: "A mic button in the opened notch mutes your microphone in every app.",
                        isOn: $settingsManager.showMicMute
                    )

                    SettingsDivider()

                    SettingsToggleRow(
                        title: "Quick Note",
                        subtitle: "A Note tab keeps one line of text until you clear it.",
                        isOn: $settingsManager.showQuickNote
                    )

                    SettingsDivider()

                    SettingsToggleRow(
                        title: "Sound Output Picker",
                        subtitle: "An Output tab switches between speakers, headphones, and displays.",
                        isOn: $settingsManager.showOutputPicker
                    )

                    SettingsDivider()

                    SettingsToggleRow(
                        title: "Sound Output Notice",
                        subtitle: "Shows where sound is playing when the output changes.",
                        isOn: $settingsManager.showAudioOutputGlance
                    )

                    SettingsDivider()

                    SettingsToggleRow(
                        title: "Upcoming Meeting",
                        subtitle: "Reminds you before a calendar event starts. Click to join when it has a meeting link.",
                        isOn: $settingsManager.showCalendarGlance
                    )

                    SettingsDivider()

                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Text("Remind Me Before")
                                .font(.system(size: 13, weight: .medium))

                            Spacer()

                            Text("\(Int(settingsManager.calendarLeadMinutes)) min")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }

                        Slider(
                            value: $settingsManager.calendarLeadMinutes,
                            in: 1...15,
                            step: 1
                        )
                        .disabled(!settingsManager.showCalendarGlance)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)

                    SettingsDivider()

                    CalendarSourcesPicker(settingsManager: settingsManager)
                        .disabled(!settingsManager.showCalendarGlance)

                    SettingsDivider()

                    SettingsToggleRow(
                        title: "Meeting Countdown",
                        subtitle: "After you dismiss the reminder, the closed notch counts down to the meeting.",
                        isOn: $settingsManager.showMeetingCountdown
                    )
                    .disabled(!settingsManager.showCalendarGlance)
                }
            }

            Text("Calendar access is read-only. Downloads and calendar each ask for permission the first time they are turned on.")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 4)
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }
}
