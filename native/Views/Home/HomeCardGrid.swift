import SwiftUI

/// Lays the home cards out up to three to a row, each a third of the
/// column. A short last row is centered rather than left-aligned, because the cards are agents,
/// whose number varies, and two cards sitting off to one side under the centered lockup look like a
/// missing third. Too narrow for two, the cards become a stack of short rows instead of a tower of
/// tall tiles.
struct HomeCardGrid: Layout {
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = min(proposal.width ?? HomeLayout.columnWidth, HomeLayout.columnWidth)
        let columns = columns(for: width)
        let rows = rowCount(for: subviews.count, columns: columns)
        guard rows > 0 else { return CGSize(width: width, height: 0) }
        let height = CGFloat(rows) * cardHeight(columns: columns) + CGFloat(rows - 1) * HomeLayout.cardSpacing
        return CGSize(width: width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let columns = columns(for: bounds.width)
        let spacing = HomeLayout.cardSpacing
        let cardWidth = (bounds.width - spacing * CGFloat(columns - 1)) / CGFloat(columns)
        let cardHeight = cardHeight(columns: columns)
        for (index, subview) in subviews.enumerated() {
            let row = index / columns
            let column = index % columns
            let cardsInRow = min(columns, subviews.count - row * columns)
            let rowWidth = cardWidth * CGFloat(cardsInRow) + spacing * CGFloat(cardsInRow - 1)
            let origin = CGPoint(
                x: bounds.minX + (bounds.width - rowWidth) / 2 + CGFloat(column) * (cardWidth + spacing),
                y: bounds.minY + CGFloat(row) * (cardHeight + spacing)
            )
            subview.place(at: origin, proposal: ProposedViewSize(width: cardWidth, height: cardHeight))
        }
    }

    // The cards set no alignment guides, so there are none to merge. Without these, SwiftUI places
    // every card (laying out its contents) each time a parent asks the grid for a guide.
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

    private func columns(for width: CGFloat) -> Int {
        let fitting = Int((width + HomeLayout.cardSpacing) / (HomeLayout.minCardWidth + HomeLayout.cardSpacing))
        return min(HomeLayout.maxColumns, max(1, fitting))
    }

    private func cardHeight(columns: Int) -> CGFloat {
        columns == 1 ? HomeLayout.compactCardHeight : HomeLayout.cardHeight
    }

    private func rowCount(for count: Int, columns: Int) -> Int {
        (count + columns - 1) / columns
    }
}
