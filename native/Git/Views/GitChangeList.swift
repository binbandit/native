import Git
import SwiftUI

/// The changed files, grouped by where they live: conflicts, staged, unstaged, untracked. Each
/// group's header stages or unstages the whole group. Every row is a child of the lazy stack
/// itself, so only the rows on screen are built, however many files changed.
struct GitChangeList: View {
    let model: GitRepositoryModel
    /// Changes waiting for the user to confirm throwing them away.
    @Binding var pendingDiscard: [FileChange]

    var body: some View {
        let status = model.status
        let selection = model.selection
        let sections = FileChange.Area.allCases.compactMap { area in
            let changes = status?.changes(in: area) ?? []
            return changes.isEmpty ? nil : (area: area, changes: changes)
        }
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(sections, id: \.area) { section in
                    Section {
                        ForEach(section.changes) { change in
                            GitChangeRow(
                                change: change, isSelected: selection == change.id, model: model,
                                pendingDiscard: $pendingDiscard)
                        }
                    } header: {
                        GitChangeSectionHeader(
                            area: section.area, changes: section.changes,
                            isFirst: section.area == sections.first?.area, model: model,
                            pendingDiscard: $pendingDiscard)
                    }
                }
                if let omitted = status?.omittedUntrackedCount, omitted > 0 {
                    Text("\(omitted) more untracked files not shown")
                        .font(.dsCaption)
                        .foregroundStyle(.dsTextTertiary)
                        .padding(.horizontal, DS.Space.md)
                        .padding(.vertical, DS.Space.sm)
                }
            }
            .padding(.horizontal, DS.Space.sm)
            .padding(.bottom, DS.Space.md)
        }
    }

    /// The list's height with nothing scrolled away, so the diff below can have the rest.
    static func contentHeight(for status: RepositoryStatus) -> CGFloat {
        let sections = CGFloat(Set(status.changes.map(\.area)).count)
        let rows = CGFloat(status.changes.count + (status.omittedUntrackedCount > 0 ? 1 : 0))
        return sections * GitChangeSectionHeader.height + rows * GitMetrics.rowHeight + DS.Space.md
    }
}

#if DEBUG
#Preview("Change list") {
    DSPreviewPair {
        GitChangeList(model: GitPreviewFixtures.model, pendingDiscard: .constant([]))
            .frame(width: GitMetrics.inspectorIdealWidth, height: 360)
    }
}
#endif
