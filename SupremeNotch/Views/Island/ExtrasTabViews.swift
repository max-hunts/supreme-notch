//
//  ExtrasTabViews.swift
//  SupremeNotch
//
//  The Usage, System and Shelf tabs of the opened notch's extras panel.
//

import AppKit
import SwiftUI
import UniformTypeIdentifiers

private let claudeOrange = Color(red: 0.851, green: 0.467, blue: 0.341)
private let dangerRed = Color(red: 0.97, green: 0.32, blue: 0.29)
private let codexBlue = Color(red: 0.45, green: 0.75, blue: 1.0)

// MARK: - Ring gauge

/// A circular gauge with the value in the middle and a short label and caption below.
struct RingGauge: View {
    let fraction: Double?
    let center: String
    let label: String
    let caption: String?
    var tint: Color = claudeOrange
    var captionColor: Color = .white.opacity(0.38)
    var help: String? = nil

    static let diameter: CGFloat = 42
    static let height: CGFloat = 78

    var body: some View {
        VStack(spacing: 4) {
            ZStack {
                Circle()
                    .stroke(Color.white.opacity(0.1), lineWidth: 5)
                if let fraction {
                    Circle()
                        .trim(from: 0, to: max(0.02, min(fraction, 1)))
                        .stroke(tint, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        .animation(.smooth(duration: 0.5, extraBounce: 0), value: fraction)
                }
                Text(verbatim: center)
                    .font(.system(size: 11.5, weight: .semibold).monospacedDigit())
                    .foregroundStyle(fraction == nil ? .white.opacity(0.4) : .white.opacity(0.92))
                    .minimumScaleFactor(0.7)
                    .lineLimit(1)
                    .padding(.horizontal, 5)
            }
            .frame(width: Self.diameter, height: Self.diameter)

            Text(verbatim: label)
                .font(.system(size: 10.5, weight: .semibold))
                .foregroundStyle(.white.opacity(0.7))
                .lineLimit(1)

            Text(verbatim: caption ?? " ")
                .font(.system(size: 9.5, weight: .medium).monospacedDigit())
                .foregroundStyle(captionColor)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity)
        .frame(height: Self.height)
        .help(Text(verbatim: help ?? ""))
    }
}

/// Orange normally, red at 90% and over.
private func usageTint(_ fraction: Double) -> Color {
    fraction >= 0.9 ? dangerRed : claudeOrange
}

// MARK: - Usage

struct UsageTabView: View {
    @ObservedObject var monitor: AIUsageMonitor

    static let rowHeight: CGFloat = 24

    static func contentHeight(rows: Int) -> CGFloat {
        CGFloat(max(1, rows)) * rowHeight + 2
    }

    var body: some View {
        Group {
            switch monitor.state {
            case .idle:
                message("Loading usage…")
            case .notInstalled:
                message("Install claude-usage-monitor to see plan usage")
            case let .failed(text):
                message(text, color: dangerRed.opacity(0.85))
            case let .loaded(snapshot):
                TimelineView(.periodic(from: .now, by: 30)) { context in
                    VStack(spacing: 0) {
                        if snapshot.claude.isEmpty, let error = snapshot.claudeError {
                            UsageBarRow(label: "Claude", fraction: nil, reset: nil, error: error)
                        }
                        ForEach(snapshot.claude) { window in
                            row(window, now: context.date)
                        }
                        ForEach(snapshot.codexWindows) { window in
                            row(window, now: context.date, tint: codexBlue)
                        }
                        if snapshot.codexWindows.isEmpty, let error = snapshot.codexError {
                            UsageBarRow(label: "Codex", fraction: nil, reset: nil, error: error)
                        }
                    }
                }
            }
        }
        .onAppear { monitor.startLive() }
        .onDisappear { monitor.stopLive() }
    }

    private func row(_ window: UsageWindow, now: Date, tint: Color = claudeOrange) -> some View {
        UsageBarRow(
            label: window.label,
            fraction: window.percent / 100,
            baseTint: tint,
            reset: Self.resetText(window.resetsAt, now: now),
            error: nil,
            help: window.resetsAt.map { "\(window.label): resets \($0.formatted(date: .abbreviated, time: .shortened))" }
        )
    }

    private func message(_ text: String, color: Color = .white.opacity(0.45)) -> some View {
        Text(verbatim: text)
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(color)
            .lineLimit(1)
            .truncationMode(.tail)
            .frame(height: Self.rowHeight)
    }

    /// "41m", "12h 28m", "6d 16h": time until the window resets.
    static func resetText(_ date: Date?, now: Date) -> String? {
        guard let date else { return nil }
        let seconds = Int(date.timeIntervalSince(now))
        if seconds <= 0 { return "now" }
        if seconds >= 86_400 { return "\(seconds / 86_400)d \((seconds % 86_400) / 3600)h" }
        if seconds >= 3600 { return "\(seconds / 3600)h \((seconds % 3600) / 60)m" }
        return "\(max(1, seconds / 60))m"
    }
}

/// Label, a thick bar, the percent, and the time until reset, in fixed columns so every
/// row lines up.
private struct UsageBarRow: View {
    let label: String
    let fraction: Double?
    var baseTint: Color = claudeOrange
    let reset: String?
    let error: String?
    var help: String? = nil

    var body: some View {
        HStack(spacing: 10) {
            Text(verbatim: label)
                .font(.system(size: 11.5, weight: .semibold))
                .foregroundStyle(.white.opacity(0.75))
                .lineLimit(1)
                .frame(width: 60, alignment: .leading)

            if let fraction {
                let tint = fraction >= 0.9 ? dangerRed : baseTint
                GeometryReader { proxy in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.white.opacity(0.09))
                        Capsule()
                            .fill(LinearGradient(colors: [tint.opacity(0.75), tint], startPoint: .leading, endPoint: .trailing))
                            .frame(width: max(7, proxy.size.width * min(fraction, 1)))
                            .animation(.smooth(duration: 0.5, extraBounce: 0), value: fraction)
                    }
                }
                .frame(height: 7)

                Text(verbatim: "\(Int((fraction * 100).rounded()))%")
                    .font(.system(size: 11.5, weight: .semibold).monospacedDigit())
                    .foregroundStyle(tint)
                    .frame(width: 36, alignment: .trailing)

                Text(verbatim: reset ?? "")
                    .font(.system(size: 10.5, weight: .medium).monospacedDigit())
                    .foregroundStyle(.white.opacity(0.35))
                    .lineLimit(1)
                    .frame(width: 50, alignment: .trailing)
            } else {
                Text(verbatim: error ?? "Unavailable")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(dangerRed.opacity(0.85))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(height: UsageTabView.rowHeight)
        .help(Text(verbatim: help ?? error ?? ""))
    }
}

// MARK: - System

struct SystemTabView: View {
    @ObservedObject var monitor: SystemStatsMonitor

    static let contentHeight = RingGauge.height
    static let ringWidth: CGFloat = 70

    var body: some View {
        let stats = monitor.stats
        let memory = stats.memoryTotalBytes > 0 ? Double(stats.memoryUsedBytes) / Double(stats.memoryTotalBytes) : 0
        let disk = stats.diskTotalBytes > 0 ? Double(stats.diskUsedBytes) / Double(stats.diskTotalBytes) : 0
        let freeDisk = stats.diskTotalBytes > stats.diskUsedBytes ? stats.diskTotalBytes - stats.diskUsedBytes : 0

        HStack(spacing: 6) {
            RingGauge(
                fraction: stats.cpuPercent / 100,
                center: "\(Int(stats.cpuPercent.rounded()))%",
                label: "CPU",
                caption: nil,
                tint: systemTint(stats.cpuPercent / 100)
            )
            .frame(width: Self.ringWidth)
            RingGauge(
                fraction: memory,
                center: "\(Int((memory * 100).rounded()))%",
                label: "Memory",
                caption: Self.number(stats.memoryUsedBytes, binary: true) + " / " + Self.gigabytes(stats.memoryTotalBytes, binary: true),
                tint: systemTint(memory)
            )
            .frame(width: Self.ringWidth)
            RingGauge(
                fraction: stats.diskTotalBytes > 0 ? disk : nil,
                center: "\(Int((disk * 100).rounded()))%",
                label: "Disk",
                caption: Self.gigabytes(freeDisk) + " free",
                tint: systemTint(disk)
            )
            .frame(width: Self.ringWidth)
            NetworkChart(history: monitor.networkHistory)
                .frame(maxWidth: .infinity)
        }
        .onAppear { monitor.startLive() }
        .onDisappear { monitor.stopLive() }
    }

    static func number(_ bytes: UInt64, binary: Bool) -> String {
        String(format: "%.0f", Double(bytes) / (binary ? 1_073_741_824 : 1_000_000_000))
    }

    /// Calm white-blue normally, orange from 75%, red from 90%.
    private func systemTint(_ fraction: Double) -> Color {
        if fraction >= 0.9 { return dangerRed }
        if fraction >= 0.75 { return .orange }
        return Color(red: 0.45, green: 0.75, blue: 1.0)
    }

    static func rate(_ bytesPerSecond: Double) -> String {
        let value = max(0, bytesPerSecond)
        if value >= 1_000_000 { return String(format: "%.1f MB/s", value / 1_000_000) }
        if value >= 1000 { return String(format: "%.0f KB/s", value / 1000) }
        return String(format: "%.0f B/s", value)
    }

    /// Memory counts in binary gigabytes (32 GB of RAM); disks in decimal, as Finder does.
    static func gigabytes(_ bytes: UInt64, binary: Bool = false) -> String {
        let value = Double(bytes) / (binary ? 1_073_741_824 : 1_000_000_000)
        return value >= 100 ? String(format: "%.0f GB", value) : String(format: "%.1f GB", value)
    }
}

/// Download (filled blue) and upload (orange line) over the last five minutes,
/// scaled to the busiest moment, with the current rates underneath.
private struct NetworkChart: View {
    let history: [NetworkSample]

    private static let down = Color(red: 0.45, green: 0.75, blue: 1.0)
    private static let up = Color(red: 1.0, green: 0.62, blue: 0.3)

    var body: some View {
        let latest = history.last
        VStack(spacing: 4) {
            GeometryReader { proxy in
                let size = proxy.size
                let peak = max(10_240, history.map { max($0.downBytesPerSecond, $0.upBytesPerSecond) }.max() ?? 0)
                ZStack(alignment: .bottomLeading) {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Color.white.opacity(0.05))
                    if history.count >= 2 {
                        area(\.downBytesPerSecond, peak: peak, in: size)
                            .fill(LinearGradient(colors: [Self.down.opacity(0.55), Self.down.opacity(0.08)], startPoint: .top, endPoint: .bottom))
                        line(\.downBytesPerSecond, peak: peak, in: size)
                            .stroke(Self.down, style: StrokeStyle(lineWidth: 1.4, lineJoin: .round))
                        line(\.upBytesPerSecond, peak: peak, in: size)
                            .stroke(Self.up, style: StrokeStyle(lineWidth: 1.4, lineJoin: .round))
                    } else {
                        Text("Collecting…")
                            .font(.system(size: 9.5, weight: .medium))
                            .foregroundStyle(.white.opacity(0.35))
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            }
            .frame(height: RingGauge.diameter)

            Text("Network · 5 min")
                .font(.system(size: 10.5, weight: .semibold))
                .foregroundStyle(.white.opacity(0.7))
                .lineLimit(1)

            HStack(spacing: 6) {
                Text(verbatim: "↓ " + SystemTabView.rate(latest?.downBytesPerSecond ?? 0))
                    .foregroundStyle(Self.down.opacity(0.9))
                Text(verbatim: "↑ " + SystemTabView.rate(latest?.upBytesPerSecond ?? 0))
                    .foregroundStyle(Self.up.opacity(0.9))
            }
            .font(.system(size: 9.5, weight: .medium).monospacedDigit())
            .lineLimit(1)
        }
        .frame(height: RingGauge.height)
    }

    /// x by time across the five-minute window, so a fresh launch fills from the right.
    private func points(_ value: KeyPath<NetworkSample, Double>, peak: Double, in size: CGSize) -> [CGPoint] {
        let now = history.last?.at ?? Date()
        let window = SystemStatsMonitor.networkWindow
        return history.map { sample in
            let age = now.timeIntervalSince(sample.at)
            let x = size.width * CGFloat(1 - age / window)
            let y = size.height - 2 - (size.height - 6) * CGFloat(min(sample[keyPath: value] / peak, 1))
            return CGPoint(x: x, y: y)
        }
    }

    private func line(_ value: KeyPath<NetworkSample, Double>, peak: Double, in size: CGSize) -> Path {
        Path { path in
            let pts = points(value, peak: peak, in: size)
            guard let first = pts.first else { return }
            path.move(to: first)
            pts.dropFirst().forEach { path.addLine(to: $0) }
        }
    }

    private func area(_ value: KeyPath<NetworkSample, Double>, peak: Double, in size: CGSize) -> Path {
        Path { path in
            let pts = points(value, peak: peak, in: size)
            guard let first = pts.first, let last = pts.last else { return }
            path.move(to: CGPoint(x: first.x, y: size.height))
            pts.forEach { path.addLine(to: $0) }
            path.addLine(to: CGPoint(x: last.x, y: size.height))
            path.closeSubpath()
        }
    }
}

// MARK: - Shelf

struct ShelfTabView: View {
    @ObservedObject var shelf: FileShelfModel
    let isDropTargeted: Bool

    static let perRow = 5
    static let tileHeight: CGFloat = 58
    static let emptyHeight: CGFloat = 64

    static func contentHeight(for count: Int) -> CGFloat {
        guard count > 0 else { return emptyHeight }
        // One slot more than the items, for the drop placeholder, until the shelf is full.
        let slots = min(count + 1, FileShelfModel.maxItems)
        let rows = (slots + perRow - 1) / perRow
        return CGFloat(rows) * tileHeight + 18
    }

    var body: some View {
        if shelf.items.isEmpty {
            DropZone(isTargeted: isDropTargeted, compact: false)
                .frame(height: Self.emptyHeight - 6)
        } else {
            VStack(alignment: .leading, spacing: 0) {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: Self.perRow), spacing: 0) {
                    ForEach(shelf.items) { item in
                        ShelfTile(item: item) {
                            withAnimation(.smooth(duration: 0.25, extraBounce: 0)) { shelf.remove(item) }
                        }
                        .frame(height: Self.tileHeight)
                    }
                    if shelf.items.count < FileShelfModel.maxItems {
                        DropZone(isTargeted: isDropTargeted, compact: true)
                            .frame(height: Self.tileHeight - 8)
                    }
                }
                HStack {
                    Spacer()
                    Button("Clear shelf") {
                        withAnimation(.smooth(duration: 0.25, extraBounce: 0)) { shelf.clear() }
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.45))
                    .help(Text("Takes everything off the shelf. Files stay where they are."))
                }
                .frame(height: 18)
            }
            .onAppear { shelf.pruneMissing() }
        }
    }
}

/// A dashed outline showing where files can be dropped. Lights up while files hover the notch.
private struct DropZone: View {
    let isTargeted: Bool
    let compact: Bool

    var body: some View {
        RoundedRectangle(cornerRadius: compact ? 10 : 12, style: .continuous)
            .strokeBorder(
                Color.white.opacity(isTargeted ? 0.7 : 0.22),
                style: StrokeStyle(lineWidth: 1.5, dash: [5, 4])
            )
            .background(
                RoundedRectangle(cornerRadius: compact ? 10 : 12, style: .continuous)
                    .fill(Color.white.opacity(isTargeted ? 0.1 : 0.03))
            )
            .overlay {
                if compact {
                    Image(systemName: "plus")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white.opacity(isTargeted ? 0.85 : 0.35))
                } else {
                    HStack(spacing: 8) {
                        Image(systemName: "tray.and.arrow.down")
                            .font(.system(size: 15, weight: .semibold))
                        Text(isTargeted ? "Drop to park here" : "Drop files here to park them")
                            .font(.system(size: 12, weight: .medium))
                    }
                    .foregroundStyle(.white.opacity(isTargeted ? 0.9 : 0.45))
                }
            }
            .scaleEffect(isTargeted ? 1.02 : 1)
            .animation(.smooth(duration: 0.2, extraBounce: 0), value: isTargeted)
    }
}

private struct ShelfTile: View {
    let item: ShelfItem
    let onRemove: () -> Void
    @State private var isHovered = false

    var body: some View {
        VStack(spacing: 4) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: item.url.path))
                .resizable()
                .frame(width: 32, height: 32)
                .shadow(color: .black.opacity(0.35), radius: 3, y: 1)
            Text(verbatim: item.url.lastPathComponent)
                .font(.system(size: 9.5, weight: .medium))
                .foregroundStyle(.white.opacity(0.8))
                .lineLimit(1)
                .truncationMode(.middle)
                .padding(.horizontal, 3)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.white.opacity(isHovered ? 0.1 : 0.05))
        )
        .padding(.vertical, 4)
        .overlay(alignment: .topTrailing) {
            if isHovered {
                Button(action: onRemove) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.7), .black.opacity(0.6))
                }
                .buttonStyle(.plain)
                .offset(x: 3, y: 1)
                .help(Text("Remove from shelf"))
            }
        }
        .contentShape(Rectangle())
        .onHover { isHovered = $0 }
        .onDrag {
            // The file itself, not a copy of its data, so Finder and other apps keep its name.
            let provider = NSItemProvider(object: item.url as NSURL)
            provider.suggestedName = item.url.lastPathComponent
            return provider
        }
        .onTapGesture(count: 2) { NSWorkspace.shared.open(item.url) }
        .help(Text(verbatim: item.url.path))
    }
}

/// Reads dropped file URLs from drag providers.
enum ShelfDrop {
    static func loadURLs(from providers: [NSItemProvider], completion: @escaping @MainActor ([URL]) -> Void) {
        let group = DispatchGroup()
        let lock = NSLock()
        var urls: [URL] = []
        for provider in providers where provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
            group.enter()
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                if let url, url.isFileURL {
                    lock.lock()
                    urls.append(url)
                    lock.unlock()
                }
                group.leave()
            }
        }
        group.notify(queue: .main) {
            MainActor.assumeIsolated { completion(urls) }
        }
    }
}
