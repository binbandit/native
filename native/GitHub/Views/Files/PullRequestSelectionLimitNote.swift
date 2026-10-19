import GitHub
import SwiftUI

/// Why a drag in the gutter stops short, while it does. Its own view, so following the drag
/// doesn't rebuild the list's rows.
struct PullRequestSelectionLimitNote: View {
    let model: PullRequestPageModel

    var body: some View {
        if let limit = model.lineSelection?.limit {
            Text(limit.explanation)
                .font(.dsCaption)
                .foregroundStyle(.dsTextSecondary)
                .padding(.horizontal, DS.Space.md)
                .padding(.vertical, DS.Space.sm)
                .background(.dsSurfaceRaised, in: Capsule())
                .overlay { Capsule().strokeBorder(.dsSeparator) }
                .padding(DS.Space.lg)
                .allowsHitTesting(false)
                .accessibilityAddTraits(.updatesFrequently)
        }
    }
}
