//
//  MenuBarWingWatcher.swift
//  Notchly
//
//  The closed island is wider than the camera notch, so its side "wings" cover menu bar
//  items next to the notch (for example the screen recording stop button). This watcher
//  reports when the pointer is in the menu bar strip beside the island, so the island can
//  tuck its wings into the notch and let those items be seen and clicked.
//
//  Mouse-move monitors need no privacy permission.
//

import AppKit
import Combine

@MainActor
final class MenuBarWingWatcher: ObservableObject {
    @Published private(set) var isPointerBesideIsland = false

    private var globalMonitor: Any?
    private var localMonitor: Any?
    private var releaseTask: Task<Void, Never>?
    private weak var screen: NSScreen?
    private var islandWidth: CGFloat = 318

    /// Extra margin outside the wings, so items right at the edge are revealed too.
    private let horizontalMargin: CGFloat = 24
    /// How long the wings stay tucked after the pointer leaves the strip.
    private let releaseDelay: Duration = .milliseconds(900)

    func configure(screen: NSScreen?, islandWidth: CGFloat) {
        self.screen = screen
        self.islandWidth = islandWidth
        startIfNeeded()
    }

    func stop() {
        if let globalMonitor { NSEvent.removeMonitor(globalMonitor) }
        if let localMonitor { NSEvent.removeMonitor(localMonitor) }
        globalMonitor = nil
        localMonitor = nil
        releaseTask?.cancel()
        isPointerBesideIsland = false
    }

    private func startIfNeeded() {
        guard globalMonitor == nil else { return }

        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved, .leftMouseDragged]) { [weak self] _ in
            MainActor.assumeIsolated { self?.evaluate() }
        }
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved, .leftMouseDragged]) { [weak self] event in
            MainActor.assumeIsolated { self?.evaluate() }
            return event
        }
    }

    private func evaluate() {
        guard let screen,
              let leftArea = screen.auxiliaryTopLeftArea,
              let rightArea = screen.auxiliaryTopRightArea else {
            setInside(false)
            return
        }

        let mouse = NSEvent.mouseLocation
        let menuBarHeight = max(screen.safeAreaInsets.top, 24)
        let inTopStrip = mouse.y >= screen.frame.maxY - menuBarHeight - 1 && mouse.y <= screen.frame.maxY + 1

        let notchMinX = leftArea.maxX
        let notchMaxX = rightArea.minX
        let halfIsland = islandWidth / 2
        let islandMinX = screen.frame.midX - halfIsland - horizontalMargin
        let islandMaxX = screen.frame.midX + halfIsland + horizontalMargin

        let inLeftWing = mouse.x >= islandMinX && mouse.x < notchMinX
        let inRightWing = mouse.x > notchMaxX && mouse.x <= islandMaxX
        // Once tucked, stay tucked while the pointer moves across the notch to the other side.
        let overNotch = mouse.x >= notchMinX && mouse.x <= notchMaxX && isPointerBesideIsland

        setInside(inTopStrip && (inLeftWing || inRightWing || overNotch))
    }

    private func setInside(_ inside: Bool) {
        if inside {
            releaseTask?.cancel()
            releaseTask = nil
            if !isPointerBesideIsland {
                isPointerBesideIsland = true
            }
            return
        }

        guard isPointerBesideIsland, releaseTask == nil else { return }
        releaseTask = Task { @MainActor [weak self] in
            guard let self else { return }
            try? await Task.sleep(for: self.releaseDelay)
            guard !Task.isCancelled else { return }
            self.isPointerBesideIsland = false
            self.releaseTask = nil
        }
    }
}
