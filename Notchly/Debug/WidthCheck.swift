//
//  WidthCheck.swift
//  BetterNotch
//
//  Debug builds only: `BetterNotch -widthCheck <folder>` opens the real island, swipes
//  through the tabs and samples the island's left and right edges every frame while its
//  width animates. Both edges should move by the same amount at every moment; report.txt
//  lists the worst gap for each switch.
//

#if DEBUG
import AppKit
import SwiftUI

@MainActor
enum WidthCheck {
    static let openIsland = Notification.Name("BetterNotchDebugOpenIsland")

    static var outputDirectory: URL? {
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: "-widthCheck"), index + 1 < arguments.count else { return nil }
        return URL(fileURLWithPath: arguments[index + 1], isDirectory: true)
    }

    static func run(environment: AppEnvironment, window: @escaping () -> NSWindow?, to directory: URL) {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(3))
            NotificationCenter.default.post(name: openIsland, object: nil)
            try? await Task.sleep(for: .seconds(1.5))
            var lines: [String] = [
                "island: " + (environment.settingsManager.showMusic && environment.musicManager.hasNowPlayingContent
                    ? "music player" : "battery panel")
            ]
            var failed = false
            let tabs: [ExtrasPanelModel.Tab] = [.agents, .usage, .ask, .ports, .system, .note, .ask, .agents]
            environment.extrasPanelModel.choose(tabs[0])
            try? await Task.sleep(for: .seconds(1))
            for tab in tabs.dropFirst() {
                guard let start = edges(window()) else {
                    lines.append("\(tab): FAIL no island")
                    failed = true
                    continue
                }
                withAnimation(.smooth(duration: 0.22, extraBounce: 0)) {
                    environment.extrasPanelModel.choose(tab)
                }
                var worst: CGFloat = 0
                var samples: [String] = []
                let began = Date()
                while Date().timeIntervalSince(began) < 0.9 {
                    try? await Task.sleep(for: .milliseconds(12))
                    guard let now = edges(window()) else { continue }
                    let leftMoved = start.left - now.left
                    let rightMoved = now.right - start.right
                    worst = max(worst, abs(leftMoved - rightMoved))
                    samples.append(String(format: "%.0f/%.0f", leftMoved, rightMoved))
                }
                let end = edges(window())
                let passed = worst <= 2
                failed = failed || !passed
                lines.append(String(format: "%@: %@ worst gap %.1f pt, width %.0f -> %.0f, center %.1f -> %.1f",
                                    "\(tab)", passed ? "PASS" : "FAIL", worst,
                                    start.right - start.left, (end?.right ?? 0) - (end?.left ?? 0),
                                    (start.left + start.right) / 2, ((end?.left ?? 0) + (end?.right ?? 0)) / 2))
                lines.append("   moved left/right: " + samples.joined(separator: " "))
                try? await Task.sleep(for: .seconds(0.6))
            }
            lines.append(failed ? "RESULT: FAIL" : "RESULT: PASS")
            try? lines.joined(separator: "\n").appending("\n")
                .write(to: directory.appendingPathComponent("report.txt"), atomically: true, encoding: .utf8)
            exit(failed ? 1 : 0)
        }
    }

    /// The island's left and right edges, in points, on a row just under its top.
    private static func edges(_ window: NSWindow?) -> (left: CGFloat, right: CGFloat)? {
        guard let view = window?.contentView,
              let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return nil }
        view.cacheDisplay(in: view.bounds, to: rep)
        let scale = CGFloat(rep.pixelsWide) / view.bounds.width
        let y = Int(6 * scale)
        var left: Int?
        var right: Int?
        for x in 0..<rep.pixelsWide where (rep.colorAt(x: x, y: y)?.alphaComponent ?? 0) > 0.5 {
            if left == nil { left = x }
            right = x
        }
        guard let left, let right else { return nil }
        return (CGFloat(left) / scale, CGFloat(right + 1) / scale)
    }
}
#endif
