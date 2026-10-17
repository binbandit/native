import Git
import SwiftUI

/// The selected file's diff, under a header naming the file and its line counts. Lines come from
/// the transcript's `DiffView`, so edits look the same wherever they're shown.
struct GitDiffPane: View {
    let change: FileChange?
    let content: GitDiffContent?

    var body: some View {
        VStack(spacing: 0) {
            if let change {
                header(change)
                SeparatorLine()
                lines
            } else {
                EmptyStateView("No file selected", systemImage: "doc.text")
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.dsSurface)
    }

    private func header(_ change: FileChange) -> some View {
        HStack(spacing: DS.Space.sm) {
            GitStatusGlyph(kind: change.kind)
            GitPathLabel(path: change.path, font: .dsBody)
            Spacer(minLength: DS.Space.md)
            Text(change.area.title)
                .font(.dsCaption)
                .foregroundStyle(.dsTextTertiary)
            if let stats = change.stats, !stats.isBinary {
                DiffStatLabel(added: stats.additions, removed: stats.deletions)
            }
        }
        .padding(.horizontal, DS.Space.md)
        .frame(height: GitMetrics.summaryHeight)
    }

    @ViewBuilder private var lines: some View {
        switch content {
        case nil:
            DotGridLoader(pattern: .waiting)
                .foregroundStyle(.dsTextTertiary)
                .frame(width: GitMetrics.loaderLarge, height: GitMetrics.loaderLarge)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .text(let diff):
            // Lines wrap rather than scroll sideways: the column is narrow, and `DiffView` keeps its
            // gutter intact for wrapped lines.
            ScrollView {
                DiffView(diff: diff, isEmbedded: true)
            }
        case .binary:
            EmptyStateView(
                "Binary file", systemImage: "doc.zipper", message: "Binary files can't be shown as a line diff.")
        case .tooLarge(let size):
            EmptyStateView(
                "File too large", systemImage: "doc.text.magnifyingglass",
                message:
                    "This file is \(size.formatted(.byteCount(style: .file))). Open it in an editor to review the change."
            )
        case .submodule:
            EmptyStateView(
                "Submodule", systemImage: "shippingbox", message: "The submodule points at a different commit.")
        case .unavailable(let reason):
            EmptyStateView("Couldn't load the diff", systemImage: "exclamationmark.triangle", message: reason)
        }
    }
}
