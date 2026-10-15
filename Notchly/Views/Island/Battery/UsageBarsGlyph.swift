//
//  UsageBarsGlyph.swift
//  Notchly
//
//  Compact subscription usage for the closed notch: one short vertical bar per limit,
//  filling bottom to top. Claude's bars run cold to hot (blue to red), Codex's run
//  green to red, and any bar at its limit turns purple.
//

import SwiftUI

struct UsageBar: Equatable, Identifiable {
    enum Scale: Equatable { case claude, codex }

    let id: String
    /// Percent of the limit used, 0 to 100+.
    let percent: Double
    let scale: Scale
}

struct UsageBarsGlyph: View {
    let bars: [UsageBar]
    let height: CGFloat

    static let barWidth: CGFloat = 4
    static let barSpacing: CGFloat = 3

    static func width(barCount: Int) -> CGFloat {
        guard barCount > 0 else { return 0 }
        return CGFloat(barCount) * barWidth + CGFloat(barCount - 1) * barSpacing
    }

    var body: some View {
        HStack(alignment: .bottom, spacing: Self.barSpacing) {
            ForEach(bars) { bar in
                let fraction = CGFloat(min(max(bar.percent / 100, 0), 1))
                ZStack(alignment: .bottom) {
                    Capsule()
                        .fill(Color.white.opacity(0.16))
                    Capsule()
                        .fill(Self.color(for: bar))
                        // Keep a round dot visible even at 0%.
                        .frame(height: max(Self.barWidth, height * fraction))
                }
                .frame(width: Self.barWidth, height: height)
                .animation(.easeOut(duration: 0.4), value: bar.percent)
            }
        }
        .frame(width: Self.width(barCount: bars.count), height: height)
        .accessibilityElement()
        .accessibilityLabel(bars.map { "\($0.id) \(Int($0.percent.rounded()))%" }.joined(separator: ", "))
    }

    // MARK: - Color scales

    private typealias Stop = (at: Double, red: Double, green: Double, blue: Double)

    /// Cold to hot through white, so it never passes green like the Codex scale:
    /// blue, light blue, white, amber, orange, red.
    private static let claudeStops: [Stop] = [
        (0.00, 0.28, 0.52, 1.00),
        (0.30, 0.55, 0.76, 1.00),
        (0.50, 0.90, 0.91, 0.95),
        (0.70, 1.00, 0.76, 0.32),
        (0.85, 1.00, 0.52, 0.22),
        (0.99, 1.00, 0.27, 0.25)
    ]

    /// Green, yellow, orange, red.
    private static let codexStops: [Stop] = [
        (0.00, 0.30, 0.84, 0.44),
        (0.60, 1.00, 0.84, 0.30),
        (0.80, 1.00, 0.56, 0.22),
        (0.99, 1.00, 0.27, 0.25)
    ]

    /// At or over the limit.
    private static let limitColor = Color(red: 0.70, green: 0.38, blue: 1.00)

    static func color(for bar: UsageBar) -> Color {
        let fraction = bar.percent / 100
        if fraction >= 1 { return limitColor }
        let stops = bar.scale == .claude ? claudeStops : codexStops
        let clamped = min(max(fraction, 0), stops.last!.at)
        guard let upper = stops.firstIndex(where: { $0.at >= clamped }), upper > 0 else {
            let first = stops[0]
            return Color(red: first.red, green: first.green, blue: first.blue)
        }
        let low = stops[upper - 1], high = stops[upper]
        let t = (clamped - low.at) / (high.at - low.at)
        return Color(
            red: low.red + (high.red - low.red) * t,
            green: low.green + (high.green - low.green) * t,
            blue: low.blue + (high.blue - low.blue) * t
        )
    }
}
