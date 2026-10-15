//
//  IslandMetrics.swift
//  BetterNotch
//
//  One spacing rule for everything inside the island: buttons and hover highlights sit
//  the same distance from the island's edge on every side, and their corners are the
//  island's corner radius minus that distance, so the curves run parallel.
//

import AppKit
import SwiftUI

enum IslandMetrics {
    /// Island edge to any button or highlight, on the sides and at the bottom.
    static let edgeInset: CGFloat = 12
    /// Island edge to text in the opened panels.
    static let contentInset: CGFloat = 16
    /// Corner radius of an alert dropping out of the notch.
    static let noticeRadius: CGFloat = 24
    /// Corner radius of the opened notch.
    static let openedRadius: CGFloat = 32
    static let buttonHeight: CGFloat = 30

    /// A corner that runs parallel to an island corner of radius `outer`, limited to a
    /// pill for short controls.
    static func concentricRadius(outer: CGFloat, height: CGFloat) -> CGFloat {
        min(max(outer - edgeInset, 6), height / 2)
    }

    /// Corner radius for buttons at the bottom of an alert.
    static var noticeButtonRadius: CGFloat {
        concentricRadius(outer: noticeRadius, height: buttonHeight)
    }
}

/// A clickable row in an opened panel: highlights on hover, with the highlight inset by
/// `IslandMetrics.edgeInset` from the island's sides and concentric with its corners.
struct IslandHoverRow: ViewModifier {
    let height: CGFloat
    @State private var isHovered = false

    private var outset: CGFloat { IslandMetrics.contentInset - IslandMetrics.edgeInset }

    func body(content: Content) -> some View {
        content
            .padding(.horizontal, outset)
            .frame(height: height)
            .background(
                RoundedRectangle(
                    cornerRadius: IslandMetrics.concentricRadius(outer: IslandMetrics.openedRadius, height: height),
                    style: .continuous
                )
                .fill(Color.white.opacity(isHovered || SnapshotRendering.showsRowHighlights ? 0.1 : 0))
            )
            .contentShape(Rectangle())
            .padding(.horizontal, -outset)
            .onHover { hovering in
                withAnimation(.easeOut(duration: 0.12)) { isHovered = hovering }
                if hovering { NSCursor.pointingHand.set() } else { NSCursor.arrow.set() }
            }
    }
}

extension View {
    func islandHoverRow(height: CGFloat) -> some View {
        modifier(IslandHoverRow(height: height))
    }
}
