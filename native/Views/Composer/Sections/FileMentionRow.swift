import ACP
import SwiftUI

/// A file or folder in the `@` list: its name (a folder's with a trailing "/"), then the folder it's
/// in, dimmed.
struct FileMentionRow: View {
    let path: String
    let isChanged: Bool
    let isHighlighted: Bool
    var counts: FileReferenceProjection.Counts?

    private var isFolder: Bool {
        FileMention.isFolder(path)
    }

    private var name: String {
        let name = path.split(separator: "/").last.map(String.init) ?? path
        return isFolder ? name + "/" : name
    }

    private var accessibilityLabel: String {
        let notes: [String?] = [isFolder ? "folder" : nil, isChanged ? "changed" : nil]
        return
            ([path] + notes.compactMap(\.self)
            + (counts.map { [DSFormat.spokenDiffStat(added: $0.added, removed: $0.removed)] } ?? [])).joined(
                separator: ", ")
    }

    private var folder: Substring {
        path.dropLast(name.count).dropLast()
    }

    var body: some View {
        HStack(spacing: DS.Space.md) {
            Image(systemName: isFolder ? "folder" : "doc")
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
            if let counts {
                DiffStatsText(stats: DiffStats(added: counts.added, removed: counts.removed))
                    .font(DS.ComposerQuote.numberFont)
                    .fixedSize()
            } else if isChanged {
                // Uncommitted files are marked, since they're often the ones being worked on.
                StatusDot(color: .dsWarning)
                    .help("Changed")
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
    }
}

#if DEBUG
#Preview("File mention rows") {
    DSPreviewPair {
        VStack(spacing: DS.Space.sm) {
            FileMentionRow(path: "native/Views/Composer/ComposerView.swift", isChanged: false, isHighlighted: true)
            FileMentionRow(path: "native/Views/Composer/Sections/", isChanged: false, isHighlighted: false)
            FileMentionRow(
                path: "native/Views/Composer/Sections/QueuedPromptsSection.swift", isChanged: true,
                isHighlighted: false, counts: .init(added: 3, removed: 1)
            )
            FileMentionRow(path: "README.md", isChanged: false, isHighlighted: false)
        }
        .frame(width: 320)
    }
}
#endif
