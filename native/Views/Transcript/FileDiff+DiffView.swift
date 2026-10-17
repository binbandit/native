import ACP
import SwiftUI

// `DiffView` lives in the design system, which doesn't know ACP; these keep the transcript's and
// Git's `FileDiff` call sites unchanged.

extension DiffView {
    /// A line diff of one file change from a tool call.
    init(diff: FileDiff, isEmbedded: Bool = false) {
        self.init(path: diff.path, oldText: diff.oldText, newText: diff.newText, isEmbedded: isEmbedded)
    }
}

extension FileDiff {
    /// Lines added and removed, as the diff view counts them.
    var stats: DiffStats { DiffStats(oldText: oldText, newText: newText) }
}

#if DEBUG
#Preview("Diffs") {
    ScrollView {
        VStack(spacing: 16) {
            DiffView(diff: TranscriptFixtures.editDiff)
            DiffView(diff: TranscriptFixtures.newFileDiff)
        }
        .padding(20)
    }
    .frame(width: 640, height: 600)
}
#endif
