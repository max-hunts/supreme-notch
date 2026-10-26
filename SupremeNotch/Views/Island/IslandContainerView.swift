//
//  IslandContainerView.swift
//  SupremeNotch
//
//  Created by n0xbyte on 25.03.2026.
//

import SwiftUI

struct IslandContainerView<Content: View>: View {
    let size: CGSize
    let cornerRadius: CGFloat
    let spacing: CGFloat
    let shadowOpacity: Double
    let showsTopCornerCutouts: Bool
    /// Moves the island's shape sideways without moving the content canvas, for the
    /// closed battery wing that only extends left of the camera notch.
    let horizontalOffset: CGFloat
    let content: Content

    init(
        size: CGSize,
        cornerRadius: CGFloat,
        spacing: CGFloat,
        shadowOpacity: Double = 0,
        showsTopCornerCutouts: Bool = true,
        horizontalOffset: CGFloat = 0,
        @ViewBuilder content: () -> Content
    ) {
        self.horizontalOffset = horizontalOffset
        self.size = size
        self.cornerRadius = cornerRadius
        self.spacing = spacing
        self.shadowOpacity = shadowOpacity
        self.showsTopCornerCutouts = showsTopCornerCutouts
        self.content = content()
    }

    var body: some View {
        ZStack(alignment: .top) {
            IslandBackgroundView(
                size: size,
                cornerRadius: cornerRadius,
                spacing: spacing,
                shadowOpacity: shadowOpacity,
                showsTopCornerCutouts: showsTopCornerCutouts
            )
            .offset(x: horizontalOffset)

            // Content sits on a fixed-width canvas that never resizes. Views that appear
            // while the island grows are placed at their final spot inside their parent at
            // once; if the parent were resizing, its moving edge would drag them sideways.
            // Only the mask, the island's shape, animates.
            ZStack(alignment: .top) {
                content
            }
            .frame(width: Self.canvasWidth, height: size.height, alignment: .top)
            .mask(
                IslandMaskView(
                    size: size,
                    cornerRadius: cornerRadius,
                    spacing: spacing,
                    showsTopCornerCutouts: showsTopCornerCutouts
                )
                .offset(x: horizontalOffset)
            )
        }
        .frame(width: size.width + cornerRadius * 2 + abs(horizontalOffset) * 2, height: size.height, alignment: .top)
    }

    /// The island window's width; wider than any island shape.
    static var canvasWidth: CGFloat { IslandCanvas.width }
}

extension View {
    /// Keeps the island's two edges moving together while it changes width. A centered
    /// view that changes width also changes position, and the position follows whatever
    /// animation triggered the change (a tab swipe's short curve) while the width follows
    /// the island's spring, so one edge would lead and the other lag. On a canvas-wide
    /// frame under the island's own animation, both follow the spring.
    func symmetricIslandResize(width: CGFloat, offset: CGFloat, animation: Animation) -> some View {
        frame(width: IslandCanvas.width)
            .animation(animation, value: width)
            .animation(animation, value: offset)
    }
}

/// Shared with the window controller, which cannot name the generic view's static.
enum IslandCanvas {
    static let width: CGFloat = 616
}
