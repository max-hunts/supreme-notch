//
//  IslandContainerView.swift
//  Notchly
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
    static var canvasWidth: CGFloat { 456 }
}
