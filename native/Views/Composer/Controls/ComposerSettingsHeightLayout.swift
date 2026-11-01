import SwiftUI

/// Gives ViewThatFits a finite height proposal while returning the selected content's intrinsic
/// height. A max-height frame alone would either expand short popovers or lose the proposal under
/// fixedSize. The popover's outside padding is part of the same budget.
struct ComposerSettingsHeightLayout: Layout {
    private var availableHeight: CGFloat {
        DS.ComposerSettings.popoverMaxHeight - 2 * DS.ComposerSettings.popoverInset
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        subviews.first?.sizeThatFits(ProposedViewSize(width: proposal.width, height: availableHeight)) ?? .zero
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        subviews.first?.place(
            at: bounds.origin, anchor: .topLeading,
            proposal: ProposedViewSize(width: bounds.width, height: availableHeight))
    }
}

/// The field's coordinate space keeps the settings arrow at its top as a multiline draft grows.
enum ComposerSettingsFieldSpace {
    nonisolated static let name = "composer-settings-field"
}

#Preview("Task settings - height budget") {
    DSPreviewPair {
        ComposerSettingsHeightLayout {
            ViewThatFits(in: .vertical) {
                Color.clear.frame(height: DS.ComposerSettings.popoverMaxHeight)
                Text("Fits below the field").frame(height: DS.ComposerSettings.rowHeight)
            }
        }
        .frame(width: DS.ComposerSettings.popoverWidth)
    }
}
