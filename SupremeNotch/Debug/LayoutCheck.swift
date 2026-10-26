//
//  LayoutCheck.swift
//  SupremeNotch
//
//  Debug builds only: `SupremeNotch -layoutCheck <folder>` shows sample agent alerts in the
//  real island window, saves each as a PNG, measures the gaps around its buttons, writes
//  report.txt and quits. The README renderer draws views outside the island, so it cannot
//  catch spacing that only goes wrong inside the real island.
//

#if DEBUG
import AppKit
import SwiftUI

@MainActor
enum LayoutCheck {
    static var outputDirectory: URL? {
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: "-layoutCheck"), index + 1 < arguments.count else { return nil }
        return URL(fileURLWithPath: arguments[index + 1], isDirectory: true)
    }

    static func run(environment: AppEnvironment, window: @escaping () -> NSWindow?, to directory: URL) {
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(3))
            var lines: [String] = []
            var failed = false
            for (name, event) in samples() {
                environment.agentEventManager.debugShow(event)
                try? await Task.sleep(for: .seconds(2))
                guard let view = window()?.contentView,
                      let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else {
                    lines.append("\(name): FAIL no island window")
                    failed = true
                    continue
                }
                view.cacheDisplay(in: view.bounds, to: rep)
                try? rep.representation(using: .png, properties: [:])?
                    .write(to: directory.appendingPathComponent("\(name).png"))
                let result = measure(rep, scale: CGFloat(rep.pixelsWide) / view.bounds.width)
                failed = failed || !result.passed
                lines.append("\(name): \(result.text)")
                environment.agentEventManager.dismissCurrentEvent()
                try? await Task.sleep(for: .seconds(1.5))
            }
            lines.append(failed ? "RESULT: FAIL" : "RESULT: PASS")
            try? lines.joined(separator: "\n").appending("\n")
                .write(to: directory.appendingPathComponent("report.txt"), atomically: true, encoding: .utf8)
            exit(failed ? 1 : 0)
        }
    }

    private static func samples() -> [(String, AgentEvent)] {
        let now = Date()
        let open = GlanceButton(title: "Open session", systemImage: "arrow.up.forward.app",
                                isPrimary: true, action: .openSession(id: "s1", source: "claude"))
        func approval(detail: String?) -> AgentApprovalRequest {
            AgentApprovalRequest(
                id: UUID().uuidString, source: "codex", sessionID: "s1", toolName: "mcp__codebase_memory_mcp__index_repository",
                toolLabel: "codebase_memory_mcp tool", summary: "index repository", detail: detail,
                project: "memberships", receivedAt: now, deadline: now.addingTimeInterval(60)
            )
        }
        return [
            ("finished-one-line", AgentEvent(id: UUID(), source: "codex", kind: .completed, title: "Task completed",
                                             message: nil, ttl: 30, createdAt: now, detail: "Copyable Markdown review",
                                             buttons: [open], sessionID: "s1")),
            ("finished-two-lines", AgentEvent(id: UUID(), source: "claude", kind: .completed, title: "Task completed",
                                              message: nil, ttl: 30, createdAt: now,
                                              detail: "Both issues are fixed in build 81, which is now running on this Mac.",
                                              buttons: [open], sessionID: "s1")),
            ("question", AgentEvent(id: UUID(), source: "claude", kind: .waiting, title: "Claude asked a question",
                                    message: nil, ttl: 30, createdAt: now,
                                    detail: "Should the usage bars refresh every 5 minutes or every 2?",
                                    buttons: [open], sessionID: "s2")),
            ("approval", AgentEvent(id: UUID(), source: "codex", kind: .accessRequest, title: "Needs approval",
                                    message: nil, ttl: 30, createdAt: now, approval: approval(detail: nil))),
            ("approval-detail", AgentEvent(id: UUID(), source: "codex", kind: .accessRequest, title: "Needs approval",
                                           message: nil, ttl: 30, createdAt: now,
                                           approval: approval(detail: "Indexes the memberships app for code search")))
        ]
    }

    /// The island is the opaque shape at the top of the transparent window. Its buttons are
    /// the lowest non-black pixels in it; they should sit `edgeInset` from the bottom edge and
    /// from both side edges.
    private static func measure(_ rep: NSBitmapImageRep, scale: CGFloat) -> (passed: Bool, text: String) {
        func pixel(_ x: Int, _ y: Int) -> (alpha: CGFloat, bright: CGFloat) {
            guard let color = rep.colorAt(x: x, y: y)?.usingColorSpace(.deviceRGB) else { return (0, 0) }
            return (color.alphaComponent, max(color.redComponent, color.greenComponent, color.blueComponent))
        }
        let centerX = rep.pixelsWide / 2
        var islandBottom = 0
        for y in 0..<rep.pixelsHigh where pixel(centerX, y).alpha > 0.5 { islandBottom = y }
        // Lowest content row: anything clearly brighter than the island's black.
        var contentBottom = 0
        var contentTop = Int.max
        for y in 0..<(islandBottom - 2) {
            for x in stride(from: 0, to: rep.pixelsWide, by: 2) where pixel(x, y).alpha > 0.5 && pixel(x, y).bright > 0.25 {
                contentBottom = max(contentBottom, y)
                contentTop = min(contentTop, y)
            }
        }
        // Mid-button, clear of its rounded corners.
        let rowY = max(0, contentBottom - Int(IslandMetrics.buttonHeight / 2 * scale))
        var islandLeft = 0, islandRight = 0, buttonLeft = Int.max, buttonRight = 0
        for x in 0..<rep.pixelsWide {
            let p = pixel(x, rowY)
            if p.alpha > 0.5 {
                if islandLeft == 0 { islandLeft = x }
                islandRight = x
                if p.bright > 0.07 { buttonLeft = min(buttonLeft, x); buttonRight = max(buttonRight, x) }
            }
        }
        // Text-to-button gap: climb out of the buttons, then up to the last text row.
        func rowHasContent(_ y: Int) -> Bool {
            stride(from: 0, to: rep.pixelsWide, by: 2).contains { pixel($0, y).alpha > 0.5 && pixel($0, y).bright > 0.25 }
        }
        var buttonTop = contentBottom
        while buttonTop > 0 && rowHasContent(buttonTop - 1) { buttonTop -= 1 }
        var textBottom = buttonTop - 1
        while textBottom > 0 && !rowHasContent(textBottom) { textBottom -= 1 }
        let textGap = CGFloat(buttonTop - textBottom) / scale
        let bottomGap = CGFloat(islandBottom - contentBottom) / scale
        let leftGap = CGFloat(buttonLeft - islandLeft) / scale
        let rightGap = CGFloat(islandRight - buttonRight) / scale
        let height = CGFloat(islandBottom + 1) / scale
        let expected = IslandMetrics.edgeInset
        // Glyphs sit above their line box, so the visible gap runs a few points over the set one.
        let textGapRange = AgentActivityView.textToButtonsGap...(AgentActivityView.textToButtonsGap + 8)
        let passed = [bottomGap, leftGap, rightGap].allSatisfy { abs($0 - expected) <= 1.5 }
            && textGapRange.contains(textGap)
        let text = String(format: "%@ height %.0f, bottom gap %.1f, sides %.1f / %.1f (want %.0f), text to buttons %.1f",
                          passed ? "PASS" : "FAIL", height, bottomGap, leftGap, rightGap, expected, textGap)
        return (passed, text)
    }
}
#endif
