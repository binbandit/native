import Git
import SwiftUI

/// A changed file in the inspector: the path, then its line counts and status
/// glyph, which give way to stage and discard buttons on hover or selection.
struct GitChangeRow: View {
    let change: FileChange
    let isSelected: Bool
    let model: GitRepositoryModel
    /// Where a discard waits for the user to confirm it.
    @Binding var pendingDiscard: [FileChange]

    @State private var isHovered = false

    var body: some View {
        HStack(spacing: DS.Space.sm) {
            label
                .frame(maxWidth: .infinity, alignment: .leading)
            // The buttons are only built while they show, over the summary, which keeps its room
            // so the path doesn't shift.
            summary
                .opacity(showsActions ? 0 : 1)
                .frame(minWidth: GitMetrics.rowActionsWidth, alignment: .trailing)
                .overlay(alignment: .trailing) {
                    if showsActions { actions }
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
        .onTapGesture(perform: select)
        .trackHover($isHovered)
        .contextMenu { menu }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
        .accessibilityAction(.default, select)
        .accessibilityAction(named: stageLabel, toggleStaged)
        .accessibilityAction(named: "Discard Changes", discard)
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
            IconButton("Discard Changes", systemImage: "arrow.uturn.backward", action: discard)
                .dsHitTarget(DS.Size.controlXS)
            IconButton(stageLabel, systemImage: change.area == .staged ? "minus" : "plus", action: toggleStaged)
                .dsHitTarget(DS.Size.controlXS)
        }
    }

    @ViewBuilder private var menu: some View {
        Button(stageLabel, action: toggleStaged)
        Button("Discard Changes…", role: .destructive, action: discard)
        Divider()
        GitFileMenuItems(path: change.path, root: model.repository?.root)
    }

    /// Hovering shows a row's actions; selecting it does too, so touch can reach them.
    private var showsActions: Bool {
        isHovered || isSelected
    }

    private var stageLabel: String {
        change.area == .staged ? "Unstage" : "Stage"
    }

    private func select() {
        model.selection = change.id
    }

    private func toggleStaged() {
        let change = change
        Task { change.area == .staged ? await model.unstage([change]) : await model.stage([change]) }
    }

    private func discard() {
        pendingDiscard = [change]
    }
}

#if DEBUG
#Preview("Change rows") {
    let model = GitPreviewFixtures.model
    DSPreviewPair {
        VStack(spacing: 0) {
            ForEach(Array(GitPreviewFixtures.status.changes.enumerated()), id: \.element.id) { index, change in
                GitChangeRow(change: change, isSelected: index == 0, model: model, pendingDiscard: .constant([]))
            }
        }
        .frame(width: GitMetrics.inspectorIdealWidth)
    }
}
#endif
