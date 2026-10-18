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
