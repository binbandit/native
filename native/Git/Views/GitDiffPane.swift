import Git
import SwiftUI

/// The selected uncommitted change's diff (`GitFileDiffView`). It reads only the model's shown
/// diff, which follows the selection once the new diff is ready.
struct GitDiffPane: View {
    let model: GitRepositoryModel

    var body: some View {
        VStack(spacing: 0) {
            if let shown = model.shownDiff {
                GitFileDiffView(
                    kind: shown.change.kind, path: shown.change.path, caption: shown.change.area.title,
                    stats: shown.change.stats, content: shown.content, onLoadDiff: model.expandSelectedDiff)
            } else {
                EmptyStateView("No file selected", systemImage: "doc.text")
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.dsSurface)
    }
}

#if NATIVE_PREVIEWS_WIP
#Preview("Diff pane") {
    DSPreviewPair {
        GitDiffPane(model: GitPreviewFixtures.model)
            .frame(width: 560, height: 360)
    }
}
#endif
