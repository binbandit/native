import SwiftUI

/// Where a view in the status bar goes: an item, or the hairline before one, at either end.
nonisolated enum StatusBarSlotRole: Equatable {
    case item(HorizontalEdge)
    case separator(HorizontalEdge)
}

nonisolated struct StatusBarSlot: LayoutValueKey {
    static let defaultValue = StatusBarSlotRole.item(.leading)
}

/// Lays the status bar's items out from both ends at their ideal widths. While they don't fit, it
/// first shortens the items that have a compact form (`.statusBarCompactForm`), then drops whole
/// items, each time the innermost leading item, then the innermost trailing one, so the outer items
/// (the ones people look for at the window's corners) stay longest. A separator shows only
/// between two shown items. Dropped views are placed past the trailing edge for the surface to
/// clip, since a layout can't hide a subview.
struct StatusBarItemsLayout: Layout {
    let spacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let sizes = subviews.map { $0.sizeThatFits(.unspecified) }
        let height = sizes.map(\.height).max() ?? 0
        let ideal = width(of: nonEmptyItems(in: subviews, sizes: sizes), subviews: subviews, sizes: sizes)
        return CGSize(width: proposal.width ?? ideal, height: proposal.height ?? height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var sizes: [CGSize] = subviews.map { $0.sizeThatFits(.unspecified) }
        let leading: [Int] = items(at: .leading, in: subviews)
        let trailing: [Int] = items(at: .trailing, in: subviews)
        let innermostFirst: [Int] = leading.reversed() + trailing

        var shown: Set<Int> = nonEmptyItems(in: subviews, sizes: sizes)
        // Shorter before gone: every item that can shorten does, before any item drops.
        for index in innermostFirst {
            let isTooWide: Bool = width(of: shown, subviews: subviews, sizes: sizes) > bounds.width
            guard isTooWide else { break }
            guard subviews[index][StatusBarCompactable.self] else { continue }
            // No form fits no width, so the item answers with its compact form's own width.
            sizes[index] = subviews[index].sizeThatFits(ProposedViewSize(width: 0, height: nil))
        }
        for index in innermostFirst where width(of: shown, subviews: subviews, sizes: sizes) > bounds.width {
            shown.remove(index)
        }
        let placed = shown.union(separators(between: shown, in: subviews))

        var x = bounds.minX
        for index in subviews.indices where placed.contains(index) && edge(of: subviews[index]) == .leading {
            place(subviews[index], size: sizes[index], at: x, in: bounds)
            x += sizes[index].width + spacing
        }
        let trailingIndices = subviews.indices.filter { placed.contains($0) && edge(of: subviews[$0]) == .trailing }
        x =
            bounds.maxX - trailingIndices.reduce(0) { $0 + sizes[$1].width } - spacing
            * CGFloat(max(trailingIndices.count - 1, 0))
        for index in trailingIndices {
            place(subviews[index], size: sizes[index], at: x, in: bounds)
            x += sizes[index].width + spacing
        }
        for index in subviews.indices where !placed.contains(index) {
            subviews[index].place(
                at: CGPoint(x: bounds.maxX + bounds.width, y: bounds.minY), proposal: ProposedViewSize(sizes[index]))
        }
    }

    // Items set no alignment guides, so there are none to merge. Without these, SwiftUI places
    // every item each time a parent asks the bar for a guide.
    func explicitAlignment(
        of guide: HorizontalAlignment, in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews,
        cache: inout ()
    ) -> CGFloat? {
        nil
    }

    func explicitAlignment(
        of guide: VerticalAlignment, in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews,
        cache: inout ()
    ) -> CGFloat? {
        nil
    }

    /// Items fill the bar's height, so the whole strip above and below their text is clickable.
    private func place(_ subview: LayoutSubview, size: CGSize, at x: CGFloat, in bounds: CGRect) {
        subview.place(
            at: CGPoint(x: x, y: bounds.midY),
            anchor: .leading,
            proposal: ProposedViewSize(width: size.width, height: bounds.height)
        )
    }

    /// The width the shown items take with their separators, and a gap between the two ends.
    private func width(of shown: Set<Int>, subviews: Subviews, sizes: [CGSize]) -> CGFloat {
        let views = shown.union(separators(between: shown, in: subviews))
        let total = views.reduce(0) { $0 + sizes[$1].width } + spacing * CGFloat(max(views.count - 1, 0))
        let ends = Set(views.map { edge(of: subviews[$0]) })
        return total + (ends.count == 2 ? spacing : 0)
    }

    /// The separators that have a shown item on each side, within the same end.
    private func separators(between shown: Set<Int>, in subviews: Subviews) -> Set<Int> {
        var result = Set<Int>()
        for index in subviews.indices {
            guard case .separator(let edge) = subviews[index][StatusBarSlot.self] else { continue }
            let before = subviews.indices.prefix(upTo: index).last {
                isItem($0, at: edge, in: subviews) && shown.contains($0)
            }
            let after = subviews.indices.suffix(from: index + 1).first { isItem($0, at: edge, in: subviews) }
            if before != nil, let after, shown.contains(after) {
                result.insert(index)
            }
        }
        return result
    }

    /// Items with something to show. One that renders nothing (an item with no data yet) still
    /// arrives as a subview, and mustn't get a separator.
    private func nonEmptyItems(in subviews: Subviews, sizes: [CGSize]) -> Set<Int> {
        Set((items(at: .leading, in: subviews) + items(at: .trailing, in: subviews)).filter { sizes[$0].width > 0 })
    }

    private func items(at edge: HorizontalEdge, in subviews: Subviews) -> [Int] {
        subviews.indices.filter { isItem($0, at: edge, in: subviews) }
    }

    private func isItem(_ index: Int, at edge: HorizontalEdge, in subviews: Subviews) -> Bool {
        subviews[index][StatusBarSlot.self] == .item(edge)
    }

    private func edge(of subview: LayoutSubview) -> HorizontalEdge {
        switch subview[StatusBarSlot.self] {
        case .item(let edge), .separator(let edge): edge
        }
    }
}
