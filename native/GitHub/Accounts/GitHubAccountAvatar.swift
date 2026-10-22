import SwiftUI

struct GitHubAccountAvatar: View {
    let name: String
    var data: Data?

    var body: some View {
        Group {
            if let data, let image = Image(decoding: data) {
                image.resizable().scaledToFill()
            } else {
                Text(name.first.map { String($0).uppercased() } ?? "?")
                    .font(.dsCaptionMedium)
                    .foregroundStyle(.dsTextSecondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(.dsSelected)
            }
        }
        .frame(width: DS.Size.controlXS, height: DS.Size.controlXS)
        .clipShape(.circle)
        .accessibilityHidden(true)
    }
}

#if DEBUG
#Preview("GitHub account avatar - Offline initials") {
    DSPreviewPair { GitHubAccountAvatar(name: "Alex Morgan") }
}
#endif
