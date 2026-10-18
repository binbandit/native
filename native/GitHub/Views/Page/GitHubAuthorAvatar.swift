import SwiftUI

/// A person's initial on a small tile, as the sidebar draws projects without a picture. Native
/// doesn't fetch avatars: one less request per comment, and nothing leaves for a third party.
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
