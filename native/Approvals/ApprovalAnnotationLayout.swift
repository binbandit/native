import SwiftUI

/// Hangs each explanation from its part's offset, one row each, and reports the width they really
/// take, so a host too narrow for the diagram falls back to the stacked layout instead of clipping.
struct ApprovalAnnotationLayout: Layout {
    struct Offset: LayoutValueKey { static let defaultValue: CGFloat = 0 }
    struct Row: LayoutValueKey { static let defaultValue = 0 }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = subviews.map { $0[Offset.self] + DS.Approval.annotationGap + $0.sizeThatFits(.unspecified).width }
        return CGSize(width: width.max() ?? 0, height: CGFloat(subviews.count) * DS.Approval.annotationLine)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        for subview in subviews {
            subview.place(
                at: CGPoint(
                    x: bounds.minX + subview[Offset.self] + DS.Approval.annotationGap,
                    y: bounds.minY + CGFloat(subview[Row.self]) * DS.Approval.annotationLine + DS.Space.xxs),
                proposal: .unspecified)
        }
    }
}
