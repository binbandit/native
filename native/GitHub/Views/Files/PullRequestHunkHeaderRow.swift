import GitHub
import SwiftUI

/// `@@ -10,6 +10,7 @@ func run()`, between hunks.
struct PullRequestHunkHeaderRow: View {
    let hunk: DiffHunk

    var body: some View {
        Text(
            "\(Text(hunk.header).foregroundStyle(.dsTextTertiary))\(Text(hunk.section.map { "  " + $0 } ?? "").foregroundStyle(.dsTextSecondary))"
        )
        .font(.dsMonoCaption)
        .lineLimit(1)
        .padding(.horizontal, DS.Space.md)
        .padding(.vertical, DS.Space.xs)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.dsHover)
    }
}

#if NATIVE_PREVIEWS_WIP
#Preview("Hunk headers") {
    DSPreviewPair {
        PullRequestPagePreview { model, _ in
            VStack(alignment: .leading, spacing: DS.Space.sm) {
                ForEach(model.files.map(\.path), id: \.self) { path in
                    if let hunk = model.hunks[path]?.first {
                        PullRequestHunkHeaderRow(hunk: hunk)
                    }
                }
            }
            .codeTextStyle(.compact)
        }
        .frame(width: 760)
    }
}
#endif
