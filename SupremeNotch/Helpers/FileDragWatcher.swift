//
//  FileDragWatcher.swift
//  SupremeNotch
//
//  Notices when you drag files toward the notch, so the island can open its shelf
//  before you get there, and catches the drop on release.
//
//  It watches mouse drags with an event monitor (no permission needed) and checks the
//  system drag pasteboard for file URLs. Only the drag pasteboard is read, never the
//  clipboard, and only during a drag that started after the last mouse down.
//
//  Drags out of a Dock folder never update that pasteboard, so they cannot be told apart
//  from an old drag by its contents. A drag that starts on a Dock window is treated as a
//  possible file drag: the island opens and lowers so the real drop reaches it, and the
//  files come from that drop rather than from the stale pasteboard.
//

import AppKit
import Combine

@MainActor
final class FileDragWatcher: ObservableObject {
    /// A file drag is in progress anywhere on screen.
    @Published private(set) var isFileDragActive = false
    /// The dragged files are near the notch.
    @Published private(set) var isNearIsland = false

    /// Files released over the island; `dropID` changes with each drop.
    @Published private(set) var dropID = 0
    private(set) var droppedURLs: [URL] = []
    private(set) var lastDropAt = Date.distantPast

    /// The island's current frame in screen coordinates, kept up to date by the island view.
    var islandFrame: CGRect = .zero

    /// How far outside the island a drag counts as near.
    private let nearMargin: CGFloat = 90
    private var globalMonitor: Any?
    private var localMonitor: Any?
    private var changeCountAtMouseDown = NSPasteboard(name: .drag).changeCount
    private var mouseDownLocation = CGPoint.zero
    /// The drag pasteboard was written during this drag, so its files are this drag's.
    private var pasteboardIsFresh = false
    private var checkedDock = false

    func start() {
        guard globalMonitor == nil else { return }
        let mask: NSEvent.EventTypeMask = [.leftMouseDown, .leftMouseDragged, .leftMouseUp]
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: mask) { [weak self] event in
            let type = event.type
            MainActor.assumeIsolated { self?.handle(type) }
        }
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: mask) { [weak self] event in
            let type = event.type
            MainActor.assumeIsolated { self?.handle(type) }
            return event
        }
    }

    func stop() {
        if let globalMonitor { NSEvent.removeMonitor(globalMonitor) }
        if let localMonitor { NSEvent.removeMonitor(localMonitor) }
        globalMonitor = nil
        localMonitor = nil
    }

    private func handle(_ type: NSEvent.EventType) {
        switch type {
        case .leftMouseDown:
            changeCountAtMouseDown = NSPasteboard(name: .drag).changeCount
            mouseDownLocation = NSEvent.mouseLocation
            pasteboardIsFresh = false
            checkedDock = false
            reset()
        case .leftMouseDragged:
            let pasteboard = NSPasteboard(name: .drag)
            // A new drag writes to the drag pasteboard; an old one left there does not count.
            if !pasteboardIsFresh, pasteboard.changeCount != changeCountAtMouseDown,
               pasteboard.types?.contains(.fileURL) == true {
                pasteboardIsFresh = true
                if !isFileDragActive { isFileDragActive = true }
            }
            if !isFileDragActive {
                guard !checkedDock else { return }
                checkedDock = true
                guard Self.isDockWindow(at: mouseDownLocation) else { return }
                isFileDragActive = true
            }
            let near = islandFrame.insetBy(dx: -nearMargin, dy: -nearMargin).contains(NSEvent.mouseLocation)
            if near != isNearIsland {
                isNearIsland = near
            }
        case .leftMouseUp:
            // Only a pasteboard written by this drag is trusted; a Dock drag's files arrive
            // through the island's own drop handler instead.
            if isFileDragActive, pasteboardIsFresh, islandFrame.insetBy(dx: -8, dy: -8).contains(NSEvent.mouseLocation) {
                let urls = NSPasteboard(name: .drag)
                    .readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL] ?? []
                if !urls.isEmpty {
                    droppedURLs = urls
                    lastDropAt = Date()
                    dropID += 1
                }
            }
            reset()
        default:
            break
        }
    }

    /// True when the frontmost on-screen window under the point belongs to the Dock.
    /// Window owners and bounds need no screen recording permission. The Dock's window
    /// spans the screen but is only on screen while the Dock or one of its folders shows.
    private static func isDockWindow(at point: CGPoint) -> Bool {
        guard let primaryHeight = NSScreen.screens.first?.frame.height,
              let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] else {
            return false
        }
        // Window bounds use a top-left origin on the primary screen.
        let flipped = CGPoint(x: point.x, y: primaryHeight - point.y)
        for window in windows {
            guard let boundsDict = window[kCGWindowBounds as String] as? NSDictionary,
                  let bounds = CGRect(dictionaryRepresentation: boundsDict),
                  bounds.contains(flipped) else { continue }
            // Skip our own transparent island window.
            if (window[kCGWindowOwnerPID as String] as? Int32) == ProcessInfo.processInfo.processIdentifier { continue }
            return window[kCGWindowOwnerName as String] as? String == "Dock"
        }
        return false
    }

    private func reset() {
        if isFileDragActive { isFileDragActive = false }
        if isNearIsland { isNearIsland = false }
    }
}
