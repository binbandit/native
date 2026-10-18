import SwiftUI

/// Views in rows that wrap at the width on offer, each at its own size: attachment chips, tags.
/// Rows line up on the leading or trailing edge (a user's message trails).
public struct FlowLayout: Layout {
    var spacing: CGFloat
    var alignment: HorizontalAlignment

    public init(spacing: CGFloat, alignment: HorizontalAlignment = .leading) {
        self.spacing = spacing
        self.alignment = alignment
    }

    public func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = rows(subviews, width: proposal.width ?? .infinity)
        let width = rows.map(\.width).max() ?? 0
        let height = rows.map(\.height).reduce(0, +) + spacing * CGFloat(max(rows.count - 1, 0))
        return CGSize(width: width, height: height)
    }

    public func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for row in rows(subviews, width: bounds.width) {
            var x = alignment == .trailing ? bounds.maxX - row.width : bounds.minX
            for (index, size) in row.items {
                subviews[index].place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
            y += row.height + spacing
        }
    }

    private struct Row {
        var items: [(index: Int, size: CGSize)] = []
        var width: CGFloat = 0
        var height: CGFloat = 0
    }

    /// Each view at its ideal size, left to right, starting a new row when the next won't fit.
    private func rows(_ subviews: Subviews, width: CGFloat) -> [Row] {
        var rows: [Row] = []
        var row = Row()
        for (index, subview) in subviews.enumerated() {
            let size = subview.sizeThatFits(.unspecified)
            let fitted = CGSize(width: min(size.width, width), height: size.height)
            if !row.items.isEmpty, row.width + spacing + fitted.width > width {
                rows.append(row)
                row = Row()
            }
            row.width += (row.items.isEmpty ? 0 : spacing) + fitted.width
            row.height = max(row.height, fitted.height)
            row.items.append((index, fitted))
        }
        if !row.items.isEmpty {
            rows.append(row)
        }
        return rows
    }
}
