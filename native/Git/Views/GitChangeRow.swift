import Git
import SwiftUI

/// A changed file in the inspector (the reference app `FileRow`): the path, then its line counts and status
/// glyph, which give way to stage and discard buttons on hover.
struct GitChangeRow: View {
    let change: FileChange
    let isSelected: Bool
    let onSelect: () -> Void
    let onToggleStaged: () -> Void
    let onDiscard: () -> Void

    @State private var isHovered = false

    var body: some View {
        HStack(spacing: DS.Space.sm) {
            label
                .frame(maxWidth: .infinity, alignment: .leading)
            ZStack(alignment: .trailing) {
                summary
                    .opacity(isHovered ? 0 : 1)
                actions
                    .opacity(isHovered ? 1 : 0)
                    .allowsHitTesting(isHovered)
            }
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
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
        .accessibilityAction(named: stageLabel, onToggleStaged)
        .accessibilityAction(named: "Discard Changes", onDiscard)
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

    private var actions: some View {
        HStack(spacing: 0) {
            IconButton("Discard Changes", systemImage: "arrow.uturn.backward", action: onDiscard)
            IconButton(stageLabel, systemImage: change.area == .staged ? "minus" : "plus", action: onToggleStaged)
        }
    }

    private var stageLabel: String {
        change.area == .staged ? "Unstage" : "Stage"
    }
}
