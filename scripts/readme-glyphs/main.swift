import SwiftUI
import AppKit
let notchW: CGFloat = 185, h: CGFloat = 32
let bg = LinearGradient(colors: [Color(red: 0.10, green: 0.12, blue: 0.20), Color(red: 0.20, green: 0.14, blue: 0.24)], startPoint: .topLeading, endPoint: .bottomTrailing)
func bars(_ p: [Double]) -> [UsageBar] {
    [UsageBar(id: "5h", percent: p[0], scale: .claude), UsageBar(id: "Week", percent: p[1], scale: .claude),
     UsageBar(id: "Model", percent: p[2], scale: .claude), UsageBar(id: "Codex", percent: p[3], scale: .codex)]
}
struct Closed: View {
    let b: [UsageBar]; let muted: Bool; var level = 72; var charging = false; var net: GlyphNetworkState = .wifi(.strong); var vol = 0.6
    var body: some View {
        let right = CompactBatteryView.wingWidth(closedHeight: h)
        let left = CompactBatteryView.leftWingWidth(barCount: b.count, micMuted: muted, closedHeight: h)
        let size = CGSize(width: notchW + right + left, height: h)
        let off = (right - left) / 2
        ZStack(alignment: .top) {
            UnevenRoundedRectangle(bottomLeadingRadius: 9, bottomTrailingRadius: 9).fill(.black)
                .frame(width: size.width, height: h).offset(x: off)
            CompactBatteryView(batteryLevel: level, isCharging: charging, lowBatteryThreshold: 20, network: net, volume: vol, isVolumeMuted: false, size: size, horizontalOffset: off, hoverOffsetY: 0, micMuted: muted, usageBars: b)
        }.frame(width: 470, height: h, alignment: .top)
    }
}
struct Caption: View { let t: String; var body: some View { Text(t).font(.system(size: 11, weight: .medium)).foregroundStyle(.white.opacity(0.75)) } }
func save<V: View>(_ v: V, _ name: String) {
    MainActor.assumeIsolated {
        let r = ImageRenderer(content: v); r.scale = 2
        let rep = NSBitmapImageRep(cgImage: r.cgImage!)
        try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: CommandLine.arguments[1] + "/" + name))
    }
}
// 1. Closed notch
save(VStack(spacing: 18) {
    VStack(spacing: 6) { Closed(b: bars([18, 46, 9, 31]), muted: false); Caption(t: "Usage bars on the left, status ring on the right") }
    VStack(spacing: 6) { Closed(b: bars([62, 88, 100, 74]), muted: true); Caption(t: "Hotter colors as limits fill, purple at the limit, muted mic beside the camera") }
    VStack(spacing: 6) {
        ZStack(alignment: .top) {
            let wing = CompactBatteryView.chargingWingWidth(closedHeight: h)
            UnevenRoundedRectangle(bottomLeadingRadius: 9, bottomTrailingRadius: 9).fill(.black).frame(width: notchW + wing * 2, height: h)
            ChargingPopView(batteryLevel: 64, lowBatteryThreshold: 20, network: .wifi(.strong), volume: 0.6, isVolumeMuted: false, size: CGSize(width: notchW + wing * 2, height: h), notchWidth: notchW)
        }.frame(width: 470, height: h, alignment: .top)
        Caption(t: "Charging pop when power connects")
    }
}.padding(.vertical, 22).frame(width: 520).background(bg), "closed-notch.png")
// 2. Ring states
func ring(_ t: String, _ level: Int, _ charging: Bool, _ net: GlyphNetworkState, _ vol: Double) -> some View {
    VStack(spacing: 8) {
        StatusRingGlyph(batteryLevel: level, isCharging: charging, lowBatteryThreshold: 20, network: net, volume: vol, isMuted: false, height: 46)
        Text(t).font(.system(size: 11, weight: .medium)).foregroundStyle(.white.opacity(0.75))
            .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
    }.frame(width: 100, alignment: .top)
}
struct Callout: View {
    let title: String; let detail: String
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.system(size: 12, weight: .semibold)).foregroundStyle(.white)
            Text(detail).font(.system(size: 10.5, weight: .medium)).foregroundStyle(.white.opacity(0.6))
        }
    }
}
save(VStack(spacing: 26) {
    HStack(spacing: 22) {
        StatusRingGlyph(batteryLevel: 72, isCharging: false, lowBatteryThreshold: 20, network: .wifi(.strong), volume: 0.6, isMuted: false, height: 110)
        VStack(alignment: .leading, spacing: 14) {
            Callout(title: "Outer arc: battery", detail: "Green while charging, red when low, yellow in Low Power Mode")
            Callout(title: "Center: network", detail: "Wi-Fi bars, an Ethernet plug, or offline")
            Callout(title: "Four dots: volume", detail: "Each lit dot is a quarter of output volume; all dim when muted")
        }
    }
    HStack(alignment: .top, spacing: 4) {
        ring("Wi-Fi", 78, false, .wifi(.strong), 0.6)
        ring("Weak Wi-Fi", 55, false, .wifi(.weak), 0.3)
        ring("Charging", 64, true, .wifi(.strong), 0.6)
        ring("Ethernet", 92, false, .ethernet, 1)
        ring("Offline,\nlow battery", 12, false, .offline, 0.5)
    }
}.padding(26).background(Color.black), "status-ring.png")
// 3. Color scales
save(VStack(alignment: .leading, spacing: 10) {
    ForEach([UsageBar.Scale.claude, .codex], id: \.self) { scale in
        HStack(spacing: 6) {
            Text(scale == .claude ? "Claude" : "Codex").font(.system(size: 11, weight: .semibold)).foregroundStyle(.white.opacity(0.8)).frame(width: 46, alignment: .leading)
            ForEach([0.0, 15, 30, 45, 60, 75, 90, 100], id: \.self) { p in
                VStack(spacing: 3) {
                    RoundedRectangle(cornerRadius: 3).fill(UsageBarsGlyph.color(for: UsageBar(id: "x", percent: p, scale: scale))).frame(width: 34, height: 12)
                    Text("\(Int(p))%").font(.system(size: 9)).foregroundStyle(.white.opacity(0.6))
                }
            }
        }
    }
}.padding(18).background(Color.black), "usage-colors.png")
// 4. Expanded battery
save(ZStack(alignment: .top) {
    UnevenRoundedRectangle(bottomLeadingRadius: 30, bottomTrailingRadius: 30).fill(.black).frame(width: 384, height: 140)
    ExpandedBatteryView(batteryLevel: 100, isCharging: true, lowBatteryThreshold: 20, network: .wifi(.strong), volume: 0.5, isVolumeMuted: false, size: CGSize(width: 384, height: 132),
        accessory: AnyView(Circle().fill(Color.white.opacity(0.12)).frame(width: 30, height: 30).overlay(Image(systemName: "mic.fill").font(.system(size: 13, weight: .semibold)).foregroundStyle(.white)))).offset(y: 14)
}.padding(.vertical, 18).frame(width: 470).background(bg), "opened-battery.png")
