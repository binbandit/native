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

#if NATIVE_PREVIEWS_WIP
#Preview("Selection limit") {
    DSPreviewPair {
        PullRequestPagePreview { model, _ in
            PullRequestSelectionLimitNote(model: model)
                .onAppear {
                    // A drag in the gutter pulled past the end of its hunk.
                    let path = "native/Views/Composer/Sections/QueuedPromptsSection.swift"
                    guard let hunk = model.hunks[path]?.first,
                        var selection = ReviewLineSelection(path: path, hunk: hunk, line: 4)
                    else { return }
                    selection.extend(to: hunk.lines.count + 3)
                    model.lineSelection = selection
                }
        }
        .frame(width: 560, height: 80)
    }
}
#endif
