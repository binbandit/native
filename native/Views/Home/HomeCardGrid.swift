import SwiftUI

/// Lays cards out as Conductor's quick actions are: up to three to a row, each a third of the
/// column. A short last row is centered rather than left-aligned, because the cards are agents and
/// folders, whose number varies, and two cards sitting off to one side under a centered wordmark
/// look like a missing third.
struct HomeCardGrid: Layout {
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = min(proposal.width ?? HomeLayout.columnWidth, HomeLayout.columnWidth)
        let rows = rowCount(for: subviews.count, columns: columns(for: width))
        guard rows > 0 else { return CGSize(width: width, height: 0) }
        let height = CGFloat(rows) * HomeLayout.cardHeight + CGFloat(rows - 1) * HomeLayout.cardSpacing
        return CGSize(width: width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let columns = columns(for: bounds.width)
        let spacing = HomeLayout.cardSpacing
        let cardWidth = (bounds.width - spacing * CGFloat(columns - 1)) / CGFloat(columns)
        for (index, subview) in subviews.enumerated() {
            let row = index / columns
            let column = index % columns
            let cardsInRow = min(columns, subviews.count - row * columns)
            let rowWidth = cardWidth * CGFloat(cardsInRow) + spacing * CGFloat(cardsInRow - 1)
            let origin = CGPoint(
                x: bounds.minX + (bounds.width - rowWidth) / 2 + CGFloat(column) * (cardWidth + spacing),
                y: bounds.minY + CGFloat(row) * (HomeLayout.cardHeight + spacing)
            )
            subview.place(at: origin, proposal: ProposedViewSize(width: cardWidth, height: HomeLayout.cardHeight))
        }
    }

    private func columns(for width: CGFloat) -> Int {
        let fitting = Int((width + HomeLayout.cardSpacing) / (HomeLayout.minCardWidth + HomeLayout.cardSpacing))
        return min(HomeLayout.maxColumns, max(1, fitting))
    }

    private func rowCount(for count: Int, columns: Int) -> Int {
        (count + columns - 1) / columns
    }
}
