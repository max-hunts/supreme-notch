//
//  PortsPanelView.swift
//  Notchly
//
//  Listening ports shown under the battery panel or music player when the notch is opened.
//

import AppKit
import SwiftUI

extension ListeningPortsMonitor {
    /// Servers worth showing in the notch. Desktop apps that happen to listen
    /// (Spotify, Figma) stay in the menu-bar list only.
    var panelPorts: [ListeningPort] {
        ports.filter { !$0.isDesktopApp }
    }
}

/// The Ports tab: listening servers with open and stop actions. Scrolls past `maxRows`.
struct PortsListView: View {
    @ObservedObject var monitor: ListeningPortsMonitor
    @State private var scrollOffset: CGFloat = 0

    static let maxRows = 8
    static let rowHeight: CGFloat = 21

    static func contentHeight(for count: Int) -> CGFloat {
        CGFloat(max(1, min(count, maxRows))) * rowHeight
    }

    var body: some View {
        let ports = monitor.panelPorts

        Group {
            if ports.isEmpty {
                Text("No dev servers listening")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.white.opacity(0.45))
                    .frame(height: Self.rowHeight)
            } else {
                let visibleHeight = CGFloat(min(ports.count, Self.maxRows)) * Self.rowHeight
                let maxOffset = max(0, CGFloat(ports.count) * Self.rowHeight - visibleHeight)
                let overflows = maxOffset > 0

                // A plain clipped VStack instead of ScrollView: a native scroll view does not take
                // part in the island's fade and scale transitions and pops in instead.
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(ports) { port in
                        PortRow(port: port, isArmed: monitor.pendingKillID == port.id) {
                            monitor.requestKill(port)
                        }
                        .frame(height: Self.rowHeight)
                    }
                }
                .offset(y: -min(scrollOffset, maxOffset))
                .frame(height: visibleHeight, alignment: .top)
                .clipped()
                .mask(
                    LinearGradient(
                        stops: [
                            .init(color: .black.opacity(overflows && scrollOffset > 1 ? 0.3 : 1), location: 0),
                            .init(color: .black, location: overflows ? 0.12 : 0),
                            .init(color: .black, location: overflows ? 0.85 : 1),
                            .init(color: .black.opacity(overflows && scrollOffset < maxOffset - 1 ? 0.25 : 1), location: 1)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .background(
                    ScrollSwipeCatcher { _, deltaY in
                        guard overflows else { return }
                        scrollOffset = min(max(scrollOffset - deltaY, 0), maxOffset)
                    }
                )
            }
        }
        .onAppear { monitor.startLive() }
        .onDisappear { monitor.stopLive() }
    }
}

private struct PortRow: View {
    let port: ListeningPort
    let isArmed: Bool
    let onKill: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Button {
                if let url = port.localURL {
                    NSWorkspace.shared.open(url)
                }
            } label: {
                Text(verbatim: "\(port.port)")
                    .font(.system(size: 11.5, weight: .semibold, design: .monospaced))
                    .foregroundStyle(Color(red: 0.45, green: 0.75, blue: 1.0))
                    .frame(width: 42, alignment: .trailing)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(Text(verbatim: "Open http://localhost:\(port.port)"))

            HStack(spacing: 5) {
                Text(verbatim: port.displayName)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.white.opacity(0.9))
                    .lineLimit(1)
                    .layoutPriority(1)

                if let context = port.context {
                    Text(verbatim: context)
                        .font(.system(size: 11, weight: .regular))
                        .foregroundStyle(.white.opacity(0.4))
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }

            Spacer(minLength: 4)

            if port.isDockerBackend {
                Image(systemName: "shippingbox.fill")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.white.opacity(0.3))
                    .help(Text(verbatim: dockerHelp))
            }

            if port.canStop {
                Button(action: onKill) {
                    Group {
                        if isArmed {
                            Text("Stop?")
                                .font(.system(size: 10.5, weight: .bold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 7)
                                .frame(height: 17)
                                .background(Color.red.opacity(0.75))
                                .clipShape(Capsule())
                        } else {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(.white.opacity(0.3))
                        }
                    }
                    .frame(minWidth: 20, minHeight: 18)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(Text(verbatim: isArmed ? "Click again to stop \(port.displayName)" : stopHelp))
            }
        }
    }

    private var dockerHelp: String {
        if let container = port.dockerContainer {
            return "Docker container \(container)" + (port.dockerProject.map { " in \($0)" } ?? "")
        }
        return "Docker"
    }

    private var stopHelp: String {
        if let container = port.dockerContainer {
            return "Stop container \(container)"
        }
        return "Stop \(port.command) (PID \(port.pid))"
    }
}
