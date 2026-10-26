//
//  ContentView+Shelf.swift
//  SupremeNotch
//
//  Dragging files onto the notch opens it on the Shelf tab; dropping parks them there.
//

import AppKit
import SwiftUI

extension ContentView {
    func handleShelfDropTargetChange(_ targeted: Bool) {
        guard settingsManager.showFileShelf else { return }

        if targeted {
            guard status == .closed, activeAgentEvent == nil else { return }
            autoExpandMusicTask?.cancel()
            extrasPanelModel.choose(.shelf)
            shelfDropOpenedIsland = true
            withAnimation(animation) {
                status = .opened
            }
        } else if shelfDropOpenedIsland {
            // The drag moved away without dropping.
            shelfDropOpenedIsland = false
            scheduleAutoClose(after: 0.7)
        }
    }

    /// The island's frame on screen, for spotting file drags near it.
    var islandScreenFrame: CGRect {
        guard let screen = currentScreen ?? NSScreen.main else { return .zero }
        let size = usesBatterySideWing ? batterySideWingSize : layout.islandSize
        let offsetX = usesBatterySideWing ? batterySideWingOffset : 0
        // The opened content sits 20 pt below the top edge; include it.
        return CGRect(
            x: screen.frame.midX + offsetX - size.width / 2,
            y: screen.frame.maxY - size.height - 20,
            width: size.width,
            height: size.height + 20
        )
    }

    /// Files released over the island, caught by the drag watcher. This also covers the case
    /// where the island window never receives the drop itself.
    func handleWatcherDrop(_ urls: [URL]) {
        guard settingsManager.showFileShelf, !urls.isEmpty else { return }
        shelfDropOpenedIsland = false
        extrasPanelModel.choose(.shelf)
        withAnimation(.smooth(duration: 0.3, extraBounce: 0)) {
            fileShelfModel.add(urls)
        }
        scheduleAutoClose(after: 2.5)
    }

    func handleShelfDrop(_ providers: [NSItemProvider]) -> Bool {
        guard settingsManager.showFileShelf else { return false }
        shelfDropOpenedIsland = false
        extrasPanelModel.choose(.shelf)

        ShelfDrop.loadURLs(from: providers) { urls in
            withAnimation(.smooth(duration: 0.3, extraBounce: 0)) {
                fileShelfModel.add(urls)
            }
        }
        // Long enough to see what landed; stays open while the pointer is on it.
        scheduleAutoClose(after: 2.5)
        return true
    }
}
