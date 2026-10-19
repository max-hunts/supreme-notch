//
//  StatusRingGlyph.swift
//  Notchly
//
//  One glyph for the closed wing: the outer arc is battery, the center is the active
//  network (Wi-Fi bars, Ethernet or offline), and the four dots are output volume.
//  Geometry ported from DuoBar by Mike Li (MIT License, github.com/Mikeli7666/DuoBar).
//  Its AirPods glyphs and network transition animations are left out, since Notchly
//  shows those events as notices.
//

import SwiftUI

struct StatusRingGlyph: View {
    let batteryLevel: Int
    let isCharging: Bool
    let lowBatteryThreshold: Int
    let network: GlyphNetworkState
    /// 0...1, or nil when the output volume is unknown.
    let volume: Double?
    let isMuted: Bool
    /// Height of the drawn ring and dots; the glyph scales to fill it exactly.
    var height: CGFloat = 22

    /// The ring top and the lowest dot edge, in 32 pt canvas units. The drawing sits
    /// above the canvas center, so it is shifted down to center what is actually drawn.
    private static let visibleTop: CGFloat = 1.95
    private static let visibleBottom: CGFloat = 25.5

    /// Width of the drawn glyph at a given height, for sizing the wing around it.
    static func width(forHeight height: CGFloat) -> CGFloat {
        height * ringDiameter / (visibleBottom - visibleTop)
    }

    private var scale: CGFloat { height / (Self.visibleBottom - Self.visibleTop) }

    /// DuoBar draws on a 32 pt canvas and scales it to the menu bar size.
    private static let canvas: CGFloat = 32
    private static let ringDiameter: CGFloat = 26.5
    private static let ringYOffset: CGFloat = -0.8
    private static let arcLineWidth: CGFloat = 26.5 * 18 / 230
    private static let arcGap = 120.2
    private static let centerYOffset: CGFloat = -1.25
    private static let symbolSize: CGFloat = 12.4
    private static let dotDiameter: CGFloat = 2.477
    private static let dotRowYOffset: CGFloat = 7.496

    private var ringPathDiameter: CGFloat { Self.ringDiameter - Self.arcLineWidth }
    private var arcStart: Double { 90 + Self.arcGap / 2 }
    private var arcEnd: Double { 450 - Self.arcGap / 2 }

    private var progress: CGFloat {
        CGFloat(min(max(Double(batteryLevel) / 100, 0), 1))
    }

    private var isLow: Bool { !isCharging && batteryLevel <= lowBatteryThreshold }

    private var ringColor: Color {
        if isCharging { return Color(nsColor: .systemGreen) }
        if isLow { return Color(nsColor: .systemRed) }
        if ProcessInfo.processInfo.isLowPowerModeEnabled { return Color(nsColor: .systemYellow) }
        return .white
    }

    var body: some View {
        ZStack {
            // While plugged in the ring turns green over a dim full track; no bolt.
            StatusArcShape(startDegrees: arcStart, endDegrees: arcEnd, progress: 1)
                .stroke(ringColor, style: ringStroke)
                .frame(width: ringPathDiameter, height: ringPathDiameter)
                .offset(y: Self.ringYOffset)
                // The ticks stand alone, with nothing showing through their gaps.
                .opacity(isCharging && !isFullOnPower ? 0.24 : 0)

            StatusArcShape(startDegrees: arcStart, endDegrees: arcEnd, progress: progress)
                .stroke(ringColor, style: isFullOnPower ? fullTickStroke : ringStroke)
                .frame(width: ringPathDiameter, height: ringPathDiameter)
                .offset(y: Self.ringYOffset)

            center
                .offset(y: Self.centerYOffset)
                .transaction { $0.animation = nil }

            VolumeDotRow(activeCount: activeDotCount, diameter: Self.dotDiameter, ringDiameter: Self.ringDiameter)
                .offset(y: Self.dotRowYOffset)
        }
        .frame(width: Self.canvas, height: Self.canvas)
        .offset(y: Self.canvas / 2 - (Self.visibleTop + Self.visibleBottom) / 2)
        .scaleEffect(scale)
        .frame(width: Self.width(forHeight: height), height: height)
        .animation(.easeOut(duration: 0.18), value: batteryLevel)
        .animation(.timingCurve(0.33, 1, 0.68, 1, duration: 0.43), value: isCharging)
        .animation(.easeOut(duration: 0.18), value: activeDotCount)
        .accessibilityElement()
        .accessibilityLabel(accessibilityText)
    }

    @ViewBuilder
    private var center: some View {
        switch network {
        case .wifi(let level):
            StatusWiFiGlyph(level: level, ringDiameter: Self.ringDiameter)
                .offset(y: wifiVerticalAdjustment)
        case .ethernet:
            symbol("cable.connector.horizontal", scale: 0.92)
        case .other:
            symbol("network", scale: 0.92)
        case .offline:
            symbol("network.slash", scale: 1)
        }
    }

    private func symbol(_ name: String, scale: CGFloat) -> some View {
        Image(systemName: name)
            .font(.system(size: Self.symbolSize * scale, weight: .semibold))
            .foregroundStyle(.white)
    }

    private var ringStroke: StrokeStyle {
        StrokeStyle(lineWidth: Self.arcLineWidth, lineCap: .round, lineJoin: .round)
    }

    /// Plugged in and full: the green ring breaks into fine ticks, so full reads differently
    /// from still charging.
    private var isFullOnPower: Bool { isCharging && batteryLevel >= 100 }

    static let fullTickCount = 24
    /// The share of each tick's step that is drawn; the rest is gap.
    static let fullTickFill: CGFloat = 0.35

    /// Ticks that start and end exactly on the arc's two ends.
    private var fullTickStroke: StrokeStyle {
        let length = ringPathDiameter / 2 * CGFloat((arcEnd - arcStart) * .pi / 180)
        let step = length / (CGFloat(Self.fullTickCount - 1) + Self.fullTickFill)
        return StrokeStyle(
            lineWidth: Self.arcLineWidth * 1.15,
            lineCap: .butt,
            dash: [step * Self.fullTickFill, step * (1 - Self.fullTickFill)]
        )
    }

    /// The Wi-Fi fan sits a little higher than the box center, as in DuoBar.
    private var wifiVerticalAdjustment: CGFloat {
        Self.ringYOffset + Self.ringDiameter * (-15 / 230) - Self.centerYOffset
    }

    private var activeDotCount: Int? {
        guard let volume else { return nil }
        let percent = Int((volume * 100).rounded())
        if isMuted || percent <= 0 { return 0 }
        switch percent {
        case 1...25: return 1
        case 26...50: return 2
        case 51...75: return 3
        default: return 4
        }
    }

    private var accessibilityText: String {
        let networkText: String
        switch network {
        case .wifi: networkText = "Wi-Fi"
        case .ethernet: networkText = "Ethernet"
        case .other: networkText = "Connected"
        case .offline: networkText = "Offline"
        }
        return "Battery \(batteryLevel)%\(isCharging ? ", charging" : ""), \(networkText)"
    }
}

private struct StatusArcShape: Shape {
    let startDegrees: Double
    let endDegrees: Double
    var progress: CGFloat

    var animatableData: CGFloat {
        get { progress }
        set { progress = newValue }
    }

    func path(in rect: CGRect) -> Path {
        let clamped = min(max(progress, 0), 1)
        guard clamped > 0 else { return Path() }
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let radius = min(rect.width, rect.height) / 2
        let visibleEnd = startDegrees + (endDegrees - startDegrees) * Double(clamped)
        let samples = 72
        var path = Path()
        for index in 0...samples {
            let degrees = startDegrees + (visibleEnd - startDegrees) * Double(index) / Double(samples)
            let radians = degrees * .pi / 180
            let point = CGPoint(
                x: center.x + CGFloat(cos(radians)) * radius,
                y: center.y + CGFloat(sin(radians)) * radius
            )
            if index == 0 { path.move(to: point) } else { path.addLine(to: point) }
        }
        return path
    }
}

/// Rounded three-band Wi-Fi fan; bands above the signal level are dimmed.
private struct StatusWiFiGlyph: View {
    let level: WiFiSignalLevel
    let ringDiameter: CGFloat

    var body: some View {
        let lineWidth = ringDiameter * 14.5 / 230
        let style = StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round)
        ZStack {
            WiFiBandShape(band: .outer).stroke(style: style).opacity(opacity(band: 2))
            WiFiBandShape(band: .middle).stroke(style: style).opacity(opacity(band: 1))
            WiFiCoreShape().fill().opacity(opacity(band: 0))
        }
        .foregroundStyle(.white)
        .frame(width: ringDiameter * 100 / 230, height: ringDiameter * 73 / 230)
    }

    private func opacity(band: Int) -> Double {
        let active: Int
        switch level {
        case .strong: active = 3
        case .medium: active = 2
        case .weak: active = 1
        }
        return band < active ? 1 : 0.28
    }
}

private struct WiFiBandShape: Shape {
    enum Band { case outer, middle }
    let band: Band

    func path(in rect: CGRect) -> Path {
        var path = Path()
        switch band {
        case .outer:
            path.move(to: CGPoint(x: rect.width * 0.075, y: rect.height * 0.321918))
            path.addQuadCurve(
                to: CGPoint(x: rect.width * 0.915, y: rect.height * 0.321918),
                control: CGPoint(x: rect.width * 0.495, y: rect.height * -0.130137)
            )
        case .middle:
            path.move(to: CGPoint(x: rect.width * 0.25, y: rect.height * 0.568493))
            path.addQuadCurve(
                to: CGPoint(x: rect.width * 0.74, y: rect.height * 0.568493),
                control: CGPoint(x: rect.width * 0.495, y: rect.height * 0.321918)
            )
        }
        return path
    }
}

private struct WiFiCoreShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.width * 0.365, y: rect.height * 0.815068))
        path.addQuadCurve(
            to: CGPoint(x: rect.width * 0.635, y: rect.height * 0.815068),
            control: CGPoint(x: rect.width * 0.5, y: rect.height * 0.650685)
        )
        path.addCurve(
            to: CGPoint(x: rect.width * 0.5, y: rect.height * 0.993151),
            control1: CGPoint(x: rect.width * 0.635, y: rect.height * 0.883562),
            control2: CGPoint(x: rect.width * 0.555, y: rect.height * 0.993151)
        )
        path.addCurve(
            to: CGPoint(x: rect.width * 0.365, y: rect.height * 0.815068),
            control1: CGPoint(x: rect.width * 0.445, y: rect.height * 0.993151),
            control2: CGPoint(x: rect.width * 0.365, y: rect.height * 0.883562)
        )
        return path
    }
}

/// Four dots along the bottom gap of the ring; lit dots show the output volume.
private struct VolumeDotRow: View {
    let activeCount: Int?
    let diameter: CGFloat
    let ringDiameter: CGFloat

    private static let xOffsets: [CGFloat] = [-55.25, -19.5, 19.5, 55.25].map { $0 / 230 }
    private static let yOffsets: [CGFloat] = [-6.5, 6.5, 6.5, -6.5].map { $0 / 230 }

    var body: some View {
        ZStack {
            ForEach(0..<4, id: \.self) { index in
                Circle()
                    .frame(width: diameter, height: diameter)
                    .opacity(activeCount.map { index < $0 ? 1 : 0.3 } ?? 0.3)
                    .offset(
                        x: ringDiameter * Self.xOffsets[index],
                        y: ringDiameter * Self.yOffsets[index]
                    )
            }
        }
        .foregroundStyle(.white)
        .frame(width: ringDiameter, height: ringDiameter)
    }
}
