import SwiftUI

struct GitHubAccountAvatar: View {
    let name: String
    var data: Data?
    var size = DS.Account.avatarSize
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Group {
            if let data, let image = Image(decoding: data) {
                image.resizable().scaledToFill()
            } else {
                Text(name.first.map { String($0).uppercased() } ?? "?")
                    .font(DS.Account.initials)
                    .foregroundStyle(.dsTextSecondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(.dsSelected)
            }
        }
        .frame(width: size, height: size)
        .clipShape(.circle)
        .overlay {
            Circle().strokeBorder(DS.Account.avatarStroke(in: colorScheme), lineWidth: DS.Account.avatarBorder)
        }
        .accessibilityHidden(true)
    }
}

#if DEBUG
#Preview("GitHub account avatar - Offline initials") {
    DSPreviewPair { GitHubAccountAvatar(name: "Alex Morgan") }
}
#endif
