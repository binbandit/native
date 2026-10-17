import SwiftUI

/// Fills the offered width and puts its content on one side, at most `fraction` of the width.
/// Bubbles hug short content; trays and cards take the full share so their rows line up.
nonisolated struct BubbleLane: Layout {
    let side: BubbleSide
    var hugsContent = false

    private var fraction: CGFloat {
        side == .trailing ? BubbleMetrics.userFraction : BubbleMetrics.agentFraction
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        guard let child = subviews.first else { return .zero }
        let size = child.sizeThatFits(ProposedViewSize(width: width(of: child, in: proposal.width), height: nil))
        return CGSize(width: proposal.width ?? size.width, height: size.height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        guard let child = subviews.first else { return }
        // Placed with the proposal it was measured with: pinning the measured height too makes
        // Markdown's lists lay out again and lose a line.
        let proposal = ProposedViewSize(width: width(of: child, in: bounds.width), height: nil)
        let size = child.sizeThatFits(proposal)
        let origin = CGPoint(x: side == .trailing ? bounds.maxX - size.width : bounds.minX, y: bounds.minY)
        child.place(at: origin, proposal: proposal)
    }

    private func width(of child: LayoutSubview, in available: CGFloat?) -> CGFloat? {
        guard let available else { return nil }
        let share = available * fraction
        // A view's ideal width is its content on one line, so short messages make short bubbles.
        return hugsContent ? min(child.sizeThatFits(.unspecified).width, share) : share
    }
}
