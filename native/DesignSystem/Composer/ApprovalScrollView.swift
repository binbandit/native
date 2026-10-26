import SwiftUI

/// Keeps a short ask at natural height, caps a long one, and yields space in a short window.
struct ApprovalScrollView<Content: View>: View {
    var maxHeight = DS.Approval.maximumHeight
    @ViewBuilder var content: Content

    var body: some View {
        ApprovalScrollLayout(maxHeight: maxHeight) {
            ScrollView(.vertical) {
                content
            }
            .scrollBounceBehavior(.basedOnSize)
        }
    }
}

private struct ApprovalScrollLayout: Layout {
    let maxHeight: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        guard let scroll = subviews.first else { return .zero }
        // Unlike fixedSize, a minimum-height probe must return zero. Otherwise AppKit raises the
        // window's minimum to the ask's ideal height, even when the scroll view has a height cap.
        let width = proposal.width.flatMap { $0.isFinite ? $0 : nil }
        if proposal.height == 0 { return CGSize(width: width ?? 0, height: 0) }
        let ideal = scroll.sizeThatFits(ProposedViewSize(width: width, height: nil))
        return CGSize(
            width: width ?? ideal.width,
            height: min(ideal.height, maxHeight, max(0, proposal.height ?? maxHeight)))
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        subviews.first?.place(at: bounds.origin, anchor: .topLeading, proposal: ProposedViewSize(bounds.size))
    }
}

#if DEBUG
#Preview("Ask scrolling - short, long and short window") {
    DSPreviewPair {
        VStack(spacing: DS.Space.xl) {
            ApprovalSurface {
                ApprovalScrollView {
                    Text("Review the settings before continuing.").font(.dsBody).padding(DS.Approval.inset)
                }
            }
            ApprovalSurface {
                ApprovalScrollView {
                    Text(String(repeating: "Review the migration and rollback before continuing. ", count: 80))
                        .font(.dsBody).padding(DS.Approval.inset)
                }
                .frame(height: DS.Approval.outputMaximumHeight)
            }
        }
        .frame(width: 420)
        .padding(DS.Space.xl)
    }
}
#endif
