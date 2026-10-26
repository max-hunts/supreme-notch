//
//  IslandMetrics.swift
//  SupremeNotch
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
    /// Corner radius of the opened notch: a row's 12 pt rounded end plus its 10 pt margin,
    /// so a hovered row's corners run parallel to the notch's.
    static let openedRadius: CGFloat = 22
    static let buttonHeight: CGFloat = 30

    /// Clickable rows in the opened panels, and their pill-shaped hover highlight.
    static let rowHeight: CGFloat = 24
    static var rowRadius: CGFloat { rowHeight / 2 }
    /// Island edge to a row highlight. Corners run parallel when the inner radius plus
    /// this gap equals the outer radius: 22 - 12 = 10.
    static var rowEdgeInset: CGFloat { openedRadius - rowRadius }
    /// Highlight edge to the row's icon and text.
    static let rowContentPadding: CGFloat = 8

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

/// A clickable row in an opened panel. The highlight sits `rowEdgeInset` from the
/// island's sides and bottom so its rounded ends run parallel to the notch's corners;
/// the row's content sits `rowContentPadding` inside it.
struct IslandRow: ViewModifier {
    let height: CGFloat
    let isHighlighted: Bool

    func body(content: Content) -> some View {
        content
            .padding(.horizontal, IslandMetrics.rowContentPadding)
            .frame(height: height)
            .background(
                RoundedRectangle(cornerRadius: IslandMetrics.rowRadius, style: .continuous)
                    .fill(Color.white.opacity(isHighlighted || SnapshotRendering.showsRowHighlights ? 0.1 : 0))
            )
            .contentShape(Rectangle())
            // The panel already insets its content by `contentInset`; move in the rest.
            .padding(.horizontal, IslandMetrics.rowEdgeInset - IslandMetrics.contentInset)
    }
}

/// Tracks the pointer over a list of equal-height rows. One tracker for the whole list
/// follows every mouse move, so the highlight never lags behind the pointer the way
/// separate enter and exit events per row can.
struct IslandRowHover: ViewModifier {
    let rowHeight: CGFloat
    @Binding var hoveredIndex: Int?

    func body(content: Content) -> some View {
        content.onContinuousHover { phase in
            switch phase {
            case let .active(location):
                let index = max(0, Int(location.y / rowHeight))
                if hoveredIndex != index { hoveredIndex = index }
                NSCursor.pointingHand.set()
            case .ended:
                hoveredIndex = nil
                NSCursor.arrow.set()
            }
        }
    }
}

extension View {
    func islandRow(height: CGFloat, isHighlighted: Bool) -> some View {
        modifier(IslandRow(height: height, isHighlighted: isHighlighted))
    }

    func islandRowHover(rowHeight: CGFloat, hoveredIndex: Binding<Int?>) -> some View {
        modifier(IslandRowHover(rowHeight: rowHeight, hoveredIndex: hoveredIndex))
    }
}
