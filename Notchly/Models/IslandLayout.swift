//
//  IslandLayout.swift
//  Notchly
//
//  Created by n0xbyte on 25.03.2026.
//

import SwiftUI

struct IslandLayout {
    let status: IslandStatus
    let isMusicModule: Bool
    let showChargingPop: Bool
    let isMusicVolumeControlExpanded: Bool
    let closedHeight: CGFloat
    let islandWidth: CGFloat
    let allowsCompactBaseWidth: Bool
    let idleWidthOverride: CGFloat?
    /// Taller agent island for approvals and summaries. Nil keeps the default preview height.
    var agentContentHeight: CGFloat? = nil
    /// Extra height below the battery panel when the notch is opened (listening ports).
    var openedExtraHeight: CGFloat = 0
    /// The pointer is in the menu bar beside the island: shrink to the camera notch so
    /// menu bar items under the wings can be seen and clicked.
    var wingsTucked = false
    /// Wider closed wings while a live activity (agent or meeting) is showing.
    var liveActivityExtraWidth: CGFloat = 0
    /// Width of the battery wing beside the camera; the charging pop opens one on each side.
    var batteryWingWidth: CGFloat? = nil
    /// Width the selected extras tab wants. Nil uses the default opened width.
    var preferredOpenedWidth: CGFloat? = nil

    let spacing: CGFloat = 10

    var baseWidth: CGFloat {
        min(max(islandWidth, allowsCompactBaseWidth ? 160 : 280), 360)
    }

    var closedSize: CGSize {
        CGSize(width: wingsTucked ? idleWidth : baseWidth + liveActivityExtraWidth, height: closedHeight)
    }

    var idleWidth: CGFloat {
        if let idleWidthOverride {
            return min(max(idleWidthOverride, 120), baseWidth)
        }

        return min(max(baseWidth * 0.58, 160), 210)
    }

    var idleSize: CGSize {
        CGSize(width: idleWidth, height: closedHeight)
    }

    var idleHoverSize: CGSize {
        CGSize(width: idleWidth + 8, height: closedHeight)
    }

    /// The opened notch is wider than the closed one, so the extras tabs have room.
    /// Capped so it stays inside the 456 pt island window with its rounded corners.
    var openedWidth: CGFloat {
        min(max(preferredOpenedWidth ?? baseWidth + 50, 340), Self.maxOpenedWidth)
    }

    /// The widest opened island that still fits the window with its rounded corners.
    static let maxOpenedWidth: CGFloat = 464

    var openedSize: CGSize {
        CGSize(width: openedWidth, height: 132 + openedExtraHeight)
    }

    var batteryPanelSize: CGSize {
        CGSize(width: openedWidth, height: 132)
    }

    var musicOpenedSize: CGSize {
        CGSize(width: openedWidth, height: musicPlayerSize.height + openedExtraHeight)
    }

    /// The player itself, without the ports panel below it.
    var musicPlayerSize: CGSize {
        CGSize(width: openedWidth, height: isMusicVolumeControlExpanded ? 228 : 190)
    }

    var musicPreviewSize: CGSize {
        CGSize(width: baseWidth, height: 68)
    }

    var focusPreviewSize: CGSize {
        closedSize
    }

    var focusCollapsedSize: CGSize {
        CGSize(width: closedSize.width * 0.5, height: closedHeight)
    }

    var brightnessPreviewSize: CGSize {
        closedSize
    }

    var brightnessCollapsedSize: CGSize {
        CGSize(width: closedSize.width * 0.5, height: closedHeight)
    }

    var volumePreviewSize: CGSize {
        closedSize
    }

    var volumeCollapsedSize: CGSize {
        CGSize(width: closedSize.width * 0.5, height: closedHeight)
    }

    var networkPreviewSize: CGSize {
        musicPreviewSize
    }

    var networkIdleSize: CGSize {
        idleSize
    }

    var networkClosedSize: CGSize {
        closedSize
    }

    var agentPreviewSize: CGSize {
        guard let agentContentHeight else { return musicPreviewSize }
        return CGSize(width: baseWidth, height: agentContentHeight)
    }

    var agentCollapsedSize: CGSize {
        CGSize(width: closedSize.width * 0.5, height: closedHeight)
    }

    var chargingSize: CGSize {
        if let batteryWingWidth {
            return CGSize(width: idleWidth + batteryWingWidth * 2, height: closedHeight)
        }
        return CGSize(width: max(280, baseWidth - 38), height: closedHeight)
    }

    var islandSize: CGSize {
        switch status {
        case .closed:
            return closedSize
        case .opened:
            return isMusicModule ? musicOpenedSize : openedSize
        case .popping:
            return showChargingPop ? chargingSize : closedSize
        case .musicPreview:
            return musicPreviewSize
        case .focusCollapse:
            return focusCollapsedSize
        case .focusPreview:
            return focusPreviewSize
        case .brightnessCollapse:
            return brightnessCollapsedSize
        case .brightnessPreview:
            return brightnessPreviewSize
        case .volumeCollapse:
            return volumeCollapsedSize
        case .volumePreview:
            return volumePreviewSize
        case .networkIdle:
            return networkIdleSize
        case .networkClosed:
            return networkClosedSize
        case .networkPreview:
            return networkPreviewSize
        case .agentCollapse:
            return agentCollapsedSize
        case .agentPreview:
            return agentPreviewSize
        }
    }

    var cornerRadius: CGFloat {
        switch status {
        case .closed:
            return 8
        case .opened:
            return 32
        case .popping:
            return 10
        case .musicPreview:
            return 24
        case .focusCollapse:
            return 8
        case .focusPreview:
            return 8
        case .brightnessCollapse:
            return 8
        case .brightnessPreview:
            return 8
        case .volumeCollapse:
            return 8
        case .volumePreview:
            return 8
        case .networkIdle:
            return 8
        case .networkClosed:
            return 8
        case .networkPreview:
            return 24
        case .agentCollapse:
            return 8
        case .agentPreview:
            return 24
        }
    }
}
