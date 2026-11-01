import SwiftUI

/// Where Peek sits in the window. Beside its row, it hangs from it, the arrow near its top as the
/// sidebar draws it; below or above an anchor with no room beside it (Home's wide rows); at the top
/// of the content without one (a filtered or collapsed list). Whatever the anchor, it stays below the
/// toolbar and inside the window, and the arrow slides along the edge to keep pointing at the row.
nonisolated struct TaskPeekFrame: Equatable {
    /// Which edge of Peek the arrow leaves from.
    enum ArrowEdge: Equatable {
        case leading, top, bottom
    }

    struct Arrow: Equatable {
        /// The middle of the arrow's base, on Peek's edge.
        let base: CGPoint
        let edge: ArrowEdge
    }

    let card: CGRect
    let arrow: Arrow?

    /// - Parameters:
    ///   - anchor: The row, in the same coordinates as `bounds`; nil when it isn't on screen.
    ///   - size: Peek's size at its width, before it's clamped to the window's height.
    ///   - bounds: The window's content, whose top edge is the toolbar's bottom edge.
    init(anchor: CGRect?, size: CGSize, in bounds: CGRect) {
        let inset = DS.Peek.windowInset
        let top = bounds.minY + DS.Peek.toolbarGap
        let bottom = bounds.maxY - inset
        let width = min(size.width, bounds.width - inset * 2)
        let height = min(size.height, bottom - top)
        let reach = DS.Peek.arrowDepth + DS.Peek.arrowGap
        // The arrow keeps clear of the rounded corners.
        let margin = DS.Peek.radius + DS.Peek.arrowWidth / 2

        guard let anchor else {
            card = CGRect(x: bounds.midX - width / 2, y: top, width: width, height: height)
            arrow = nil
            return
        }
        if anchor.maxX + reach + width <= bounds.maxX - inset {
            let y = Self.clamp(anchor.midY - DS.Peek.arrowInset, top, bottom - height)
            card = CGRect(x: anchor.maxX + reach, y: y, width: width, height: height)
            let arrowY = Self.clamp(anchor.midY, card.minY + margin, card.maxY - margin)
            arrow = Arrow(base: CGPoint(x: card.minX, y: arrowY), edge: .leading)
            return
        }
        let x = Self.clamp(anchor.midX - width / 2, bounds.minX + inset, bounds.maxX - inset - width)
        let arrowX = Self.clamp(anchor.midX, x + margin, x + width - margin)
        if anchor.maxY + reach + height <= bottom {
            card = CGRect(x: x, y: anchor.maxY + reach, width: width, height: height)
            arrow = Arrow(base: CGPoint(x: arrowX, y: card.minY), edge: .top)
        } else if anchor.minY - reach - height >= top {
            card = CGRect(x: x, y: anchor.minY - reach - height, width: width, height: height)
            arrow = Arrow(base: CGPoint(x: arrowX, y: card.maxY), edge: .bottom)
        } else {
            card = CGRect(x: x, y: top, width: width, height: height)
            arrow = nil
        }
    }

    private static func clamp(_ value: CGFloat, _ low: CGFloat, _ high: CGFloat) -> CGFloat {
        min(max(value, low), max(low, high))
    }
}

/// Peek's arrow, drawn over its edge: the fill covers the edge's hairline at the base, and only the
/// two outer sides are stroked, so the arrow and Peek read as one shape.
struct TaskPeekArrow: View {
    let edge: TaskPeekFrame.ArrowEdge

    var body: some View {
        ZStack {
            TaskPeekArrowShape(edge: edge, isClosed: true).fill(.dsOverlay)
            TaskPeekArrowShape(edge: edge, isClosed: false).stroke(.dsOverlayEdge, lineWidth: 1)
        }
        .frame(width: size.width, height: size.height)
        .accessibilityHidden(true)
    }

    /// The arrow's box, a point deeper than the arrow so its fill covers Peek's hairline.
    var size: CGSize {
        switch edge {
        case .leading: CGSize(width: DS.Peek.arrowDepth + 1, height: DS.Peek.arrowWidth)
        case .top, .bottom: CGSize(width: DS.Peek.arrowWidth, height: DS.Peek.arrowDepth + 1)
        }
    }

    /// Where the box's center goes for an arrow whose base is at `base`.
    func center(for base: CGPoint) -> CGPoint {
        let half = (DS.Peek.arrowDepth + 1) / 2
        return switch edge {
        case .leading: CGPoint(x: base.x - DS.Peek.arrowDepth + half, y: base.y)
        case .top: CGPoint(x: base.x, y: base.y - DS.Peek.arrowDepth + half)
        case .bottom: CGPoint(x: base.x, y: base.y + DS.Peek.arrowDepth - half)
        }
    }
}

nonisolated private struct TaskPeekArrowShape: Shape {
    let edge: TaskPeekFrame.ArrowEdge
    let isClosed: Bool

    func path(in rect: CGRect) -> Path {
        // The tip, then the two base corners, which sit a point inside Peek.
        let (tip, first, second): (CGPoint, CGPoint, CGPoint) =
            switch edge {
            case .leading:
                (
                    CGPoint(x: rect.minX, y: rect.midY), CGPoint(x: rect.maxX, y: rect.minY),
                    CGPoint(x: rect.maxX, y: rect.maxY)
                )
            case .top:
                (
                    CGPoint(x: rect.midX, y: rect.minY), CGPoint(x: rect.minX, y: rect.maxY),
                    CGPoint(x: rect.maxX, y: rect.maxY)
                )
            case .bottom:
                (
                    CGPoint(x: rect.midX, y: rect.maxY), CGPoint(x: rect.minX, y: rect.minY),
                    CGPoint(x: rect.maxX, y: rect.minY)
                )
            }
        // The stroke stops where the base meets Peek's own hairline.
        let inside: CGFloat = isClosed ? 0 : 1
        func toward(_ point: CGPoint) -> CGPoint {
            switch edge {
            case .leading: CGPoint(x: point.x - inside, y: point.y)
            case .top: CGPoint(x: point.x, y: point.y - inside)
            case .bottom: CGPoint(x: point.x, y: point.y + inside)
            }
        }
        var path = Path()
        path.move(to: toward(first))
        path.addLine(to: tip)
        path.addLine(to: toward(second))
        if isClosed { path.closeSubpath() }
        return path
    }
}
