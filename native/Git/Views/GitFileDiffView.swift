import Git
import SwiftUI

/// One file's diff under a header naming the file, where its change lives and its line counts.
/// Lines come from the transcript's `DiffView`, so edits look the same wherever they're shown. The
/// inspector's panes for uncommitted changes and for a turn's or a branch's changes both use it.
struct GitFileDiffView: View {
    let kind: FileChange.Kind
    let path: String
    /// Where the change lives ("Staged"), when that's worth saying.
    var caption: String?
    let stats: LineStats?
    /// Nil while it loads.
    let content: GitDiffContent?
    /// Loads a collapsed diff in full.
    let onLoadDiff: () -> Void

    @Environment(\.gitChangesCompact) private var compact

    var body: some View {
        VStack(spacing: 0) {
            if !compact {
                header
                SeparatorLine()
            }
            lines
        }
    }

    private var header: some View {
        HStack(spacing: DS.Space.sm) {
            GitStatusGlyph(kind: kind)
            GitPathLabel(path: path, font: .dsBody)
            Spacer(minLength: DS.Space.md)
            if let caption {
                Text(caption)
                    .font(.dsCaption)
                    .foregroundStyle(.dsTextTertiary)
            }
            if let stats, !stats.isBinary {
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
                DiffView(
                    path: diff.path, oldText: diff.oldText, newText: diff.newText, layout: diff.layout,
                    isEmbedded: true, isLazy: true)
            }
        case .collapsed(let changedLines, let size):
            EmptyStateView(
                "Large diff", systemImage: "doc.text.magnifyingglass",
                message: Self.collapsedMessage(changedLines: changedLines, size: size)
            ) {
                Button("Load Diff", action: onLoadDiff)
                    .buttonStyle(.ds(.secondary))
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

    private static func collapsedMessage(changedLines: Int?, size: Int) -> String {
        let file = size.formatted(.byteCount(style: .file))
        guard let changedLines else { return "This file is \(file), so its diff waits until you ask for it." }
        return "\(changedLines.formatted()) lines changed in a \(file) file, so the diff waits until you ask for it."
    }
}

#if DEBUG
#Preview("Wide diff - Loading, binary, large and failure") {
    DSPreviewPair {
        ForEach(0..<5) { state in
            let contents: [GitDiffContent?] = [
                nil, .binary, .collapsed(changedLines: 800, size: 100_000),
                .unavailable("The file moved. Select another file or refresh Changes."), .submodule,
            ]
            GitFileDiffView(
                kind: .modified, path: "Sources/Example.swift", stats: nil, content: contents[state], onLoadDiff: {}
            )
            .environment(\.gitChangesCompact, true)
            .frame(width: DS.TaskWell.panelWidth, height: DS.TaskWell.devMaxHeight)
        }
    }
}
#endif
