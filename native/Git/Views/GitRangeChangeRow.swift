import Git
import SwiftUI

/// A file a turn or a branch changed: its path, line counts and status glyph. Selecting it shows
/// its diff. What's committed can't be staged or discarded here, so the row has no actions of its
/// own beyond the file menu.
struct GitRangeChangeRow: View {
    let change: TreeChange
    let isSelected: Bool
    /// The repository's root on this machine, for opening the file.
    let root: URL?
    let onSelect: () -> Void

    @State private var isHovered = false

    var body: some View {
        HStack(spacing: DS.Space.sm) {
            label
                .frame(maxWidth: .infinity, alignment: .leading)
            summary
        }
        .padding(.leading, DS.Space.md)
        .padding(.trailing, DS.Space.xs)
        .frame(height: GitMetrics.rowHeight)
        .background {
            RoundedRectangle(cornerRadius: DS.Radius.row, style: .continuous)
                .fill(isSelected ? .dsSelected : isHovered ? .dsHover : .clear)
        }
        .contentShape(.rect)
        .onTapGesture(perform: onSelect)
        .trackHover($isHovered)
        .contextMenu {
            GitFileMenuItems(path: change.path, root: root)
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
        .accessibilityAction(.default, onSelect)
    }

    @ViewBuilder private var label: some View {
        if let original = change.originalPath {
            HStack(spacing: DS.Space.sm) {
                GitPathLabel(path: original)
                Image(systemName: "arrow.right")
                    .font(.dsCaption)
                    .foregroundStyle(.dsTextTertiary)
                GitPathLabel(path: change.path)
            }
        } else {
            GitPathLabel(path: change.path)
        }
    }

    private var summary: some View {
        HStack(spacing: DS.Space.sm) {
            if let stats = change.stats {
                if stats.isBinary {
                    Text("binary")
                        .font(.dsMicro)
                        .foregroundStyle(.dsTextTertiary)
                } else {
                    DiffStatLabel(added: stats.additions, removed: stats.deletions)
                }
            }
            GitStatusGlyph(kind: change.kind)
        }
    }
}
