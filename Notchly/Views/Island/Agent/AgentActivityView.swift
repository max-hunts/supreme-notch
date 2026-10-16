//
//  AgentActivityView.swift
//  Notchly
//
//  Created by n0xbyte on 29.05.2026.
//

import SwiftUI

struct AgentActivityView: View {
    let event: AgentEvent?
    let size: CGSize
    var pendingCount: Int = 0
    var onDecision: ((AgentApprovalRequest, AgentApprovalDecision) -> Void)? = nil
    var onGlanceButton: ((AgentEvent, GlanceButton) -> Void)? = nil

    /// How far below the island's top edge the alert is drawn.
    static let contentTopOffset: CGFloat = 10
    /// Where the header row starts, measured from the island's top edge.
    static let headerTop: CGFloat = contentTopOffset + 4

    /// Room to add above the alert so the header clears the camera housing, which covers
    /// the top `closedHeight` points of the island on a screen with a notch.
    static func notchClearance(closedHeight: CGFloat, screenHasNotch: Bool) -> CGFloat {
        screenHasNotch ? max(0, closedHeight - headerTop) : 0
    }

    /// Island content height for an event, or nil to use the default preview height.
    static func contentHeight(for event: AgentEvent?) -> CGFloat? {
        guard let event else { return nil }
        if let approval = event.approval {
            return approval.detail == nil ? 140 : 156
        }
        if !event.batteryParts.isEmpty || event.progressKey != nil {
            return 92
        }
        if event.detail != nil && !event.buttons.isEmpty {
            return 140
        }
        if event.detail != nil {
            return 98
        }
        return nil
    }

    var body: some View {
        Group {
            if let event, let approval = event.approval {
                AgentApprovalContent(
                    event: event,
                    request: approval,
                    pendingCount: pendingCount,
                    onDecision: onDecision
                )
                .padding(.horizontal, IslandMetrics.edgeInset)
                .frame(width: size.width, height: size.height, alignment: .top)
            } else if let event, let progressKey = event.progressKey {
                DownloadProgressContent(event: event, progressKey: progressKey)
                    .padding(.horizontal, IslandMetrics.edgeInset)
                    .frame(width: size.width, height: size.height, alignment: .top)
                    .allowsHitTesting(false)
            } else if let event, !event.batteryParts.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 10) {
                        AgentSourceIcon(event: event)
                        Spacer(minLength: 0)
                    }
                    .frame(height: 22)

                    HStack(alignment: .center, spacing: 10) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(event.title)
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(.white.opacity(0.5))
                            Text(event.detail ?? event.sourceLabel)
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(.white.opacity(0.94))
                                .lineLimit(1)
                        }

                        Spacer(minLength: 6)

                        HStack(spacing: 10) {
                            ForEach(Array(event.batteryParts.enumerated()), id: \.offset) { _, part in
                                BatteryRingView(
                                    part: part,
                                    deviceSymbol: event.glance?.symbolName ?? "headphones"
                                )
                            }
                        }
                    }
                }
                .padding(.horizontal, IslandMetrics.edgeInset)
                .frame(width: size.width, height: size.height, alignment: .top)
                .allowsHitTesting(false)
            } else if let event, let detail = event.detail, !event.buttons.isEmpty {
                GlanceWithButtons(event: event, detail: detail, onButton: onGlanceButton)
                    .padding(.horizontal, IslandMetrics.edgeInset)
                    .frame(width: size.width, height: size.height, alignment: .top)
            } else if let event, let detail = event.detail {
                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 10) {
                        AgentSourceIcon(event: event)
                        Spacer(minLength: 0)
                    }
                    .frame(height: 22)

                    Text(event.title)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.5))
                        .lineLimit(1)

                    Text(detail)
                        .font(.system(size: 12.5, weight: .medium))
                        .foregroundStyle(.white.opacity(0.92))
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, IslandMetrics.edgeInset)
                .frame(width: size.width, height: size.height, alignment: .top)
                .allowsHitTesting(false)
            } else if let event {
                VStack(spacing: 6) {
                    HStack(spacing: 10) {
                        AgentSourceIcon(event: event)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    HStack(spacing: 6) {
                        Image(systemName: event.glance == nil ? "sparkles" : "info.circle")
                            .font(.system(size: 11, weight: .semibold))

                        Text(event.title)
                            .font(.system(size: 12, weight: .medium))
                            .lineLimit(1)
                    }
                    .foregroundStyle(.white.opacity(0.5))
                    .frame(maxWidth: .infinity, alignment: .center)
                }
                .padding(.horizontal, 12)
                .frame(width: size.width, height: size.height, alignment: .top)
                .allowsHitTesting(false)
            }
        }
    }
}

private struct AgentApprovalContent: View {
    let event: AgentEvent
    let request: AgentApprovalRequest
    let pendingCount: Int
    let onDecision: ((AgentApprovalRequest, AgentApprovalDecision) -> Void)?

    /// Short delay so a click that was already on its way cannot approve a request.
    @State private var isArmed = SnapshotRendering.isActive
    @State private var isResolving = false

    /// Claude requests use Claude's orange, like the other agent notices.
    private var primaryColor: Color {
        event.source.lowercased() == "claude"
            ? Color(red: 0.851, green: 0.467, blue: 0.341)
            : Color(red: 0.2, green: 0.55, blue: 1.0).opacity(0.75)
    }

    /// The middle button hands the request back to the agent's own prompt.
    private var agentButtonTitle: String {
        switch event.source.lowercased() {
        case "claude": return "In Claude"
        case "codex": return "In Codex"
        default: return "Terminal"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                AgentSourceIcon(event: event)

                Text(request.toolLabel)
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundStyle(Color(red: 1.0, green: 0.72, blue: 0.42))
                    .lineLimit(1)
                    .layoutPriority(1)

                if let project = request.project, !project.isEmpty {
                    Text("· \(project)")
                        .font(.system(size: 11.5, weight: .medium))
                        .foregroundStyle(.white.opacity(0.5))
                        .lineLimit(1)
                }

                Spacer(minLength: 0)

                if pendingCount > 1 {
                    Text("\(pendingCount) waiting")
                        .font(.system(size: 10.5, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.85))
                        .padding(.horizontal, 7)
                        .frame(height: 18)
                        .background(Color.orange.opacity(0.32))
                        .clipShape(Capsule())
                }
            }
            .frame(height: 22)

            Text(request.summary)
                .font(.system(size: 12, weight: .medium, design: .monospaced))
                .foregroundStyle(.white.opacity(0.94))
                .lineLimit(2)
                .truncationMode(.tail)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
                .help(request.summary)
                .padding(.top, 6)

            if let detail = request.detail {
                Text(detail)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.white.opacity(0.5))
                    .lineLimit(1)
                    .padding(.top, 3)
            }

            Spacer(minLength: 10)

            HStack(spacing: 8) {
                decisionButton("Deny", isPrimary: false, decision: .deny)
                decisionButton(agentButtonTitle, isPrimary: false, decision: .answerInTerminal)
                decisionButton("Approve", isPrimary: true, decision: .approve)
            }
            .frame(height: IslandMetrics.buttonHeight)
            // The alert is drawn `contentTopOffset` below the island's top, so the bottom
            // padding adds it back to keep the buttons `edgeInset` from the bottom edge.
            .padding(.bottom, IslandMetrics.edgeInset + AgentActivityView.contentTopOffset)
        }
        .padding(.top, 4)
        .onAppear {
            isArmed = SnapshotRendering.isActive
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(450))
                isArmed = true
            }
        }
    }

    private func decisionButton(
        _ title: String,
        isPrimary: Bool,
        decision: AgentApprovalDecision
    ) -> some View {
        Button {
            guard isArmed, !isResolving else { return }
            isResolving = true
            onDecision?(request, decision)
        } label: {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(isPrimary ? .white : .white.opacity(0.8))
                .lineLimit(1)
                .frame(maxWidth: .infinity)
                .frame(height: IslandMetrics.buttonHeight)
                .background(isPrimary ? primaryColor : Color.white.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: IslandMetrics.noticeButtonRadius, style: .continuous))
                .contentShape(RoundedRectangle(cornerRadius: IslandMetrics.noticeButtonRadius, style: .continuous))
        }
        .buttonStyle(IslandControlButtonStyle(pressedScale: 0.96, hoverScale: 1.02, hoverBackgroundOpacity: 0.06))
        .opacity(isArmed ? 1 : 0.55)
        .accessibilityLabel("\(title) \(request.toolLabel)")
    }
}

struct AgentSourceIcon: View {
    let event: AgentEvent

    var body: some View {
        if let glance = event.glance {
            Image(systemName: glance.symbolName)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Color(red: glance.red, green: glance.green, blue: glance.blue))
                .frame(width: 22, height: 22)
        } else {
            switch event.source.lowercased() {
            case "codex":
                Image("CodexAgentIcon")
                    .resizable()
                    .renderingMode(.original)
                    .scaledToFit()
                    .frame(width: 22, height: 22)
            case "cursor":
                Image("CursorAgentIcon")
                    .resizable()
                    .renderingMode(.original)
                    .scaledToFit()
                    .frame(width: 22, height: 22)
            case "claude":
                Image(systemName: "sparkles")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color(red: 0.85, green: 0.48, blue: 0.32))
                    .frame(width: 22, height: 22)
            default:
                Image(systemName: "sparkles")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.78))
                    .frame(width: 22, height: 22)
            }
        }
    }
}


/// Apple-style battery ring: a green arc around the part's icon, red when low.
struct BatteryRingView: View {
    let part: GlanceBatteryPart
    let deviceSymbol: String

    private let diameter: CGFloat = 32
    private let lineWidth: CGFloat = 3.5

    var body: some View {
        ZStack {
            Circle()
                .stroke(.white.opacity(0.14), lineWidth: lineWidth)

            Circle()
                .trim(from: 0, to: CGFloat(max(part.level, 2)) / 100)
                .stroke(ringColor, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))

            Image(systemName: partSymbol)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.white.opacity(0.9))
        }
        .frame(width: diameter, height: diameter)
        .overlay(alignment: .topTrailing) {
            if part.isCharging {
                Image(systemName: "bolt.fill")
                    .font(.system(size: 7, weight: .bold))
                    .foregroundStyle(.black)
                    .frame(width: 12, height: 12)
                    .background(ringColor)
                    .clipShape(Circle())
                    .offset(x: 3, y: -3)
            }
        }
        .accessibilityElement()
        .accessibilityLabel("\(accessibilityName) battery \(part.level) percent\(part.isCharging ? ", charging" : "")")
    }

    private var ringColor: Color {
        part.level <= 20 ? Color(red: 1.0, green: 0.27, blue: 0.23) : Color(red: 0.2, green: 0.84, blue: 0.29)
    }

    private var partSymbol: String {
        switch part.kind {
        case .left:
            return "airpod.left"
        case .right:
            return "airpod.right"
        case .case:
            return deviceSymbol == "airpodspro" ? "airpodspro.chargingcase.wireless.fill" : "airpods.chargingcase.fill"
        case .single:
            return deviceSymbol
        }
    }

    private var accessibilityName: String {
        switch part.kind {
        case .left: return "Left"
        case .right: return "Right"
        case .case: return "Case"
        case .single: return "Headphones"
        }
    }
}


/// Live download ring. Observes the progress store so it updates without re-presenting.
private struct DownloadProgressContent: View {
    let event: AgentEvent
    let progressKey: String
    @ObservedObject private var store = GlanceProgressStore.shared

    var body: some View {
        let entry = store.entries[progressKey]

        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                AgentSourceIcon(event: event)
                Spacer(minLength: 0)
            }
            .frame(height: 22)

            HStack(alignment: .center, spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(event.title)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.5))
                    Text(event.detail ?? "Download")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.94))
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Text(sizeLine(entry))
                        .font(.system(size: 11, weight: .medium).monospacedDigit())
                        .foregroundStyle(.white.opacity(0.55))
                        .lineLimit(1)
                }

                Spacer(minLength: 6)

                ProgressRing(fraction: entry?.fraction)
            }
        }
    }

    private func sizeLine(_ entry: GlanceProgressStore.Entry?) -> String {
        guard let entry else { return "Starting…" }
        let done = ByteCountFormatter.string(fromByteCount: entry.bytes, countStyle: .file)
        var line = done
        if let total = entry.totalBytes {
            line += " of " + ByteCountFormatter.string(fromByteCount: total, countStyle: .file)
        }
        if entry.bytesPerSecond > 1024 {
            line += " · " + ByteCountFormatter.string(fromByteCount: Int64(entry.bytesPerSecond), countStyle: .file) + "/s"
        }
        return line
    }
}

private struct ProgressRing: View {
    /// nil shows an indeterminate spinning arc.
    let fraction: Double?
    @State private var spin = false

    var body: some View {
        ZStack {
            Circle()
                .stroke(.white.opacity(0.14), lineWidth: 3.5)

            if let fraction {
                Circle()
                    .trim(from: 0, to: CGFloat(max(fraction, 0.02)))
                    .stroke(Color(red: 0.38, green: 0.68, blue: 1.0), style: StrokeStyle(lineWidth: 3.5, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(.easeOut(duration: 0.6), value: fraction)
            } else {
                Circle()
                    .trim(from: 0, to: 0.28)
                    .stroke(Color(red: 0.38, green: 0.68, blue: 1.0), style: StrokeStyle(lineWidth: 3.5, lineCap: .round))
                    .rotationEffect(.degrees(spin ? 270 : -90))
                    .animation(.linear(duration: 1.1).repeatForever(autoreverses: false), value: spin)
                    .onAppear { spin = true }
            }

            Image(systemName: "arrow.down")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(.white.opacity(0.9))
        }
        .frame(width: 32, height: 32)
    }
}


/// A glance that stays until the user acts, such as a meeting reminder with Join and Dismiss.
private struct GlanceWithButtons: View {
    let event: AgentEvent
    let detail: String
    let onButton: ((AgentEvent, GlanceButton) -> Void)?
    @State private var isArmed = SnapshotRendering.isActive

    /// Claude alerts use Claude's orange; other glances keep the system blue.
    private var primaryColor: Color {
        event.source.lowercased() == "claude" && event.glance == nil
            ? Color(red: 0.851, green: 0.467, blue: 0.341)
            : Color(red: 0.2, green: 0.55, blue: 1.0).opacity(0.75)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                AgentSourceIcon(event: event)
                Text(event.title)
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.5))
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .frame(height: 22)

            Text(detail)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white.opacity(0.94))
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 6)

            Spacer(minLength: 10)

            HStack(spacing: 8) {
                ForEach(event.buttons) { button in
                    Button {
                        guard isArmed else { return }
                        onButton?(event, button)
                    } label: {
                        Text(button.title)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(button.isPrimary ? .white : .white.opacity(0.8))
                            .frame(maxWidth: .infinity)
                            .frame(height: IslandMetrics.buttonHeight)
                            .background(button.isPrimary ? primaryColor : Color.white.opacity(0.1))
                            .clipShape(RoundedRectangle(cornerRadius: IslandMetrics.noticeButtonRadius, style: .continuous))
                            .contentShape(RoundedRectangle(cornerRadius: IslandMetrics.noticeButtonRadius, style: .continuous))
                    }
                    .buttonStyle(IslandControlButtonStyle(pressedScale: 0.96, hoverScale: 1.02, hoverBackgroundOpacity: 0.06))
                    .opacity(isArmed ? 1 : 0.55)
                }
            }
            .frame(height: IslandMetrics.buttonHeight)
            // The alert is drawn `contentTopOffset` below the island's top, so the bottom
            // padding adds it back to keep the buttons `edgeInset` from the bottom edge.
            .padding(.bottom, IslandMetrics.edgeInset + AgentActivityView.contentTopOffset)
        }
        .padding(.top, 4)
        .onAppear {
            isArmed = SnapshotRendering.isActive
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(450))
                isArmed = true
            }
        }
    }
}
