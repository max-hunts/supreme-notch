//
//  UsageBarsGlyph.swift
//  Notchly
//
//  Compact subscription usage for the closed notch: one short vertical bar per limit,
//  filling bottom to top. Claude's bars run cold to hot (blue through green to red),
//  Codex's run green to red, and any bar at its limit turns purple.
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

    /// Cold to hot through green: blue, cyan, sea green, lime, amber, red.
    private static let claudeStops: [Stop] = [
        (0.00, 0.184, 0.357, 1.000),
        (0.22, 0.122, 0.714, 0.949),
        (0.42, 0.133, 0.827, 0.651),
        (0.60, 0.651, 0.890, 0.235),
        (0.78, 1.000, 0.690, 0.125),
        (0.99, 0.910, 0.149, 0.227)
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
        // Blend in OKLab so the in-between colors stay as vivid as the stops.
        let a = oklab(low.red, low.green, low.blue), b = oklab(high.red, high.green, high.blue)
        let mixed = srgb(L: a.L + (b.L - a.L) * t, a: a.a + (b.a - a.a) * t, b: a.b + (b.b - a.b) * t)
        return Color(red: mixed.red, green: mixed.green, blue: mixed.blue)
    }

    private static func oklab(_ r: Double, _ g: Double, _ b: Double) -> (L: Double, a: Double, b: Double) {
        func linear(_ c: Double) -> Double { c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4) }
        let (r, g, b) = (linear(r), linear(g), linear(b))
        let l = cbrt(0.4122214708 * r + 0.5363325363 * g + 0.0514459929 * b)
        let m = cbrt(0.2119034982 * r + 0.6806995451 * g + 0.1073969566 * b)
        let s = cbrt(0.0883024619 * r + 0.2817188376 * g + 0.6299787005 * b)
        return (0.2104542553 * l + 0.7936177850 * m - 0.0040720468 * s,
                1.9779984951 * l - 2.4285922050 * m + 0.4505937099 * s,
                0.0259040371 * l + 0.7827717662 * m - 0.8086757660 * s)
    }

    private static func srgb(L: Double, a: Double, b: Double) -> (red: Double, green: Double, blue: Double) {
        func gamma(_ c: Double) -> Double {
            let c = min(max(c, 0), 1)
            return c <= 0.0031308 ? 12.92 * c : 1.055 * pow(c, 1 / 2.4) - 0.055
        }
        let l = pow(L + 0.3963377774 * a + 0.2158037573 * b, 3)
        let m = pow(L - 0.1055613458 * a - 0.0638541728 * b, 3)
        let s = pow(L - 0.0894841775 * a - 1.2914855480 * b, 3)
        return (gamma(4.0767416621 * l - 3.3077115913 * m + 0.2309699292 * s),
                gamma(-1.2684380046 * l + 2.6097574011 * m - 0.3413193965 * s),
                gamma(-0.0041960863 * l - 0.7034186147 * m + 1.7076147010 * s))
    }
}
