//
//  ScrollSwipeCatcher.swift
//  SupremeNotch
//
//  Created by n0xbyte on 24.03.2026.
//

import SwiftUI
import AppKit

struct ScrollSwipeCatcher: NSViewRepresentable {
    var onScroll: (CGFloat, CGFloat) -> Void = { _, _ in }
    /// The raw event, for callers that need the gesture phase.
    var onScrollEvent: ((NSEvent) -> Void)? = nil

    func makeNSView(context: Context) -> ScrollTrackingView {
        let view = ScrollTrackingView()
        view.onScroll = onScroll
        view.onScrollEvent = onScrollEvent
        return view
    }

    func updateNSView(_ nsView: ScrollTrackingView, context: Context) {
        nsView.onScroll = onScroll
        nsView.onScrollEvent = onScrollEvent
    }
}

final class ScrollTrackingView: NSView {
    var onScroll: ((CGFloat, CGFloat) -> Void)?
    var onScrollEvent: ((NSEvent) -> Void)?

    private var scrollMonitor: Any?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
    }

    deinit {
        removeMonitor()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()

        removeMonitor()

        guard window != nil else { return }

        scrollMonitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
            guard let self else { return event }
            guard let window = self.window else { return event }
            guard !self.isHidden, self.alphaValue > 0 else { return event }

            let pointInWindow = window.mouseLocationOutsideOfEventStream
            let pointInView = self.convert(pointInWindow, from: nil)

            guard self.bounds.contains(pointInView) else { return event }

            self.onScroll?(event.scrollingDeltaX, event.scrollingDeltaY)
            self.onScrollEvent?(event)
            return event
        }
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }

    private func removeMonitor() {
        if let scrollMonitor {
            NSEvent.removeMonitor(scrollMonitor)
            self.scrollMonitor = nil
        }
    }
}

/// True while views are drawn offscreen for README images; AppKit-backed views such as
/// the swipe catcher cannot be drawn there.
enum SnapshotRendering {
    nonisolated(unsafe) static var isActive = false
    /// Draws hover highlights on every row, to check their insets in a render.
    nonisolated(unsafe) static var showsRowHighlights = false
}
