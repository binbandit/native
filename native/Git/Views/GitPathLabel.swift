import SwiftUI

/// A repository path with its directory muted and the file name in full.
/// The directory gives way first when space runs out.
struct GitPathLabel: View {
    let path: String
    var font: Font = .dsCallout

    var body: some View {
        let slash = path.lastIndex(of: "/")
        HStack(alignment: .firstTextBaseline, spacing: 0) {
            if let slash {
                Text(path[...slash])
                    .foregroundStyle(.dsTextTertiary)
                    .truncationMode(.head)
                    .layoutPriority(0)
            }
            Text(slash.map { path[path.index(after: $0)...] } ?? path[...])
                .foregroundStyle(.dsTextPrimary)
                .truncationMode(.middle)
                .layoutPriority(1)
        }
        .font(font)
        .tracking(DS.Tracking.tight)
        .lineLimit(1)
        .help(path)
    }
}

#if DEBUG
#Preview("Path labels") {
    DSPreviewPair {
        VStack(alignment: .leading, spacing: DS.Space.sm) {
            GitPathLabel(path: "native/Git/Model/GitStore.swift")
            GitPathLabel(path: "README.md")
            GitPathLabel(path: "native/Views/Transcript/Styles/Bubbles/BubbleTypingIndicator.swift")
        }
        .frame(width: 240, alignment: .leading)
    }
}
#endif
