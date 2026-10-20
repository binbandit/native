import Git
import SwiftUI

/// How each kind of change is drawn: square glyphs in git's colors.
extension FileChange.Kind {
    var symbolName: String {
        switch self {
        case .added, .untracked, .copied: "plus.square"
        case .modified, .typeChanged: "dot.square"
        case .deleted: "minus.square"
        case .renamed: "arrow.right.square"
        case .conflicted: "exclamationmark.triangle"
        }
    }

    var tint: Color {
        switch self {
        case .added, .copied: .dsSuccess
        case .modified, .typeChanged: .dsWarning
        case .deleted, .conflicted: .dsDanger
        case .renamed: .dsInfo
        case .untracked: .dsTextTertiary
        }
    }

    var label: String {
        switch self {
        case .added: "Added"
        case .modified: "Modified"
        case .deleted: "Deleted"
        case .renamed: "Renamed"
        case .copied: "Copied"
        case .typeChanged: "Type changed"
        case .untracked: "Untracked"
        case .conflicted: "Conflicted"
        }
    }
}

extension FileChange.Area {
    var title: String {
        switch self {
        case .conflicted: "Conflicts"
        case .staged: "Staged"
        case .unstaged: "Changes"
        case .untracked: "Untracked"
        }
    }
}

/// The 12pt status square at the end of a file row.
struct GitStatusGlyph: View {
    let kind: FileChange.Kind

    var body: some View {
        Image(systemName: kind.symbolName)
            .font(.system(size: GitMetrics.statusGlyph, weight: .medium))
            .foregroundStyle(kind.tint)
            .frame(width: DS.Size.rowLeading, height: DS.Size.rowLeading)
            .help(kind.label)
            .accessibilityLabel(kind.label)
    }
}

#if DEBUG
#Preview("Status glyphs") {
    DSPreviewPair {
        VStack(alignment: .leading, spacing: DS.Space.sm) {
            ForEach(GitPreviewFixtures.status.changes, id: \.id) { change in
                HStack(spacing: DS.Space.md) {
                    GitStatusGlyph(kind: change.kind)
                    Text(change.kind.label)
                        .font(.dsBody)
                        .foregroundStyle(.dsTextSecondary)
                }
            }
        }
    }
}
#endif
