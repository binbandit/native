import ACP
import SwiftUI

/// An earlier turn's tool work as one line, "Read 6 files, edited 3 files and ran 4 commands", that
/// opens the turn's rows back up in place. It reads like a group of tool work (`ToolGroupView`):
/// the same line, glyph and chevron.
struct TurnActivityFold: View {
    let summary: TurnSummary
    let isUnfolded: Bool
    let toggle: () -> Void

    var body: some View {
        ToolLine(
            glyph: .mixed, sentence: summary.activityDescription ?? "Worked", isExpandable: true,
            isExpanded: isUnfolded, toggle: toggle
        ) {
            EmptyView()
        }
        .accessibilityHint(isUnfolded ? "Folds the turn's tool calls" : "Shows the turn's tool calls")
    }
}

#if DEBUG
#Preview("Turn activity fold - Folded and unfolded") {
    let summary = TurnSummary(items: ToolGroupPreviewFixtures.done.flatMap(\.items))
    DSPreviewPair {
        VStack(alignment: .leading, spacing: DS.Space.xxs) {
            TurnActivityFold(summary: summary, isUnfolded: false) {}
            TurnActivityFold(summary: summary, isUnfolded: true) {}
        }
        .padding(DS.Space.xl)
        .frame(width: 560)
    }
}
#endif
