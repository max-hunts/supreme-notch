//
//  ClosedWings.swift
//  SupremeNotch
//
//  The closed notch's wings: content left and right of the camera, each wing only as wide
//  as what it holds. Each side keeps one gap all round, to the island's edge, to its
//  bottom and to the camera housing, as the usage bars and status ring do.
//

import SwiftUI
import AppKit

enum ClosedWings {
    /// A wing holding content `width` wide; 0 when there is nothing to hold.
    static func width(content: CGFloat, inset: CGFloat, cameraHousingInset: CGFloat) -> CGFloat {
        guard content > 0 else { return 0 }
        return inset + content + inset - cameraHousingInset
    }

    /// The side gap that matches the space above and below content this tall.
    static func inset(closedHeight: CGFloat, contentHeight: CGFloat) -> CGFloat {
        max(3, (closedHeight - contentHeight) / 2)
    }

    static func textWidth(_ text: String, font: NSFont) -> CGFloat {
        NSAttributedString(string: text, attributes: [.font: font]).size().width.rounded(.up)
    }

    /// The meeting countdown's width for the minutes it shows now ("3:52").
    static func countdownWidth(until date: Date, font: NSFont) -> CGFloat {
        let minutes = max(0, Int(date.timeIntervalSinceNow / 60))
        let digits = String(minutes).count
        return textWidth(String(repeating: "0", count: digits) + ":00", font: font)
    }
}

/// Lays out the two wings on the island's canvas: `leading` against the left edge,
/// `trailing` against the right, each with its own gap.
struct ClosedWingsView<Leading: View, Trailing: View>: View {
    let size: CGSize
    let leadingInset: CGFloat
    let trailingInset: CGFloat
    var horizontalOffset: CGFloat = 0
    var hoverOffsetY: CGFloat = 0
    @ViewBuilder let leading: () -> Leading
    @ViewBuilder let trailing: () -> Trailing

    var body: some View {
        HStack(spacing: 0) {
            leading()
            Spacer(minLength: 0)
            trailing()
        }
        .padding(.leading, leadingInset)
        .padding(.trailing, trailingInset)
        .frame(width: size.width, height: size.height)
        .offset(x: horizontalOffset, y: hoverOffsetY)
    }
}
