import SwiftUI

/// A file in the `@` list: its name, then the folder it's in, dimmed.
struct FileMentionRow: View {
    let path: String
    let isChanged: Bool
    let isHighlighted: Bool

    private var name: Substring {
        path.split(separator: "/").last ?? Substring(path)
    }

    private var folder: Substring {
        path.dropLast(name.count).dropLast()
    }

    var body: some View {
        HStack(spacing: DS.Space.md) {
            Image(systemName: "doc")
                .font(.dsCaption)
                .foregroundStyle(.dsTextTertiary)
                .frame(width: DS.Size.rowLeading)
            Text(name)
                .font(.dsBody)
                .foregroundStyle(isHighlighted ? .dsTextPrimary : .dsTextSecondary)
                .layoutPriority(1)
            Text(folder)
                .font(.dsBody)
                .foregroundStyle(.dsTextTertiary)
                .lineLimit(1)
                .truncationMode(.head)
            Spacer(minLength: 0)
            if isChanged {
                // the reference app marks uncommitted files the same way in its file list.
                StatusDot(color: .dsWarning)
                    .help("Changed")
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(isChanged ? "\(path), changed" : path)
    }
}
