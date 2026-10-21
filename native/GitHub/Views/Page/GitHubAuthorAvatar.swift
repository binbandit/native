import SwiftUI

/// A person's initial on a small tile, as the sidebar draws projects without a picture. Native
/// uses initials for comment authors, avoiding a separate image request per comment.
struct GitHubAuthorAvatar: View {
    let login: String?

    var body: some View {
        Text(login?.first.map { String($0).uppercased() } ?? "?")
            .font(.dsMicro)
            .foregroundStyle(.dsTextSecondary)
            .frame(width: DS.Size.rowLeading, height: DS.Size.rowLeading)
            .background(.dsSelected, in: .circle)
            .accessibilityHidden(true)
    }
}

#if NATIVE_PREVIEWS_WIP
#Preview("Author avatars") {
    DSPreviewPair {
        HStack(spacing: DS.Space.md) {
            GitHubAuthorAvatar(login: "binbandit")
            GitHubAuthorAvatar(login: "preview-reviewer")
            GitHubAuthorAvatar(login: "dependabot[bot]")
            GitHubAuthorAvatar(login: nil)
        }
    }
}
#endif
