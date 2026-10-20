import SwiftUI

/// One kind of cleanup in the sheet: what it will do ("Delete 6 local branches"), a checkbox that
/// includes or leaves out the whole group, and its items.
struct GitCleanupGroupSection: View {
    let model: GitCleanupModel
    let group: GitCleanupItem.Group

    var body: some View {
        let items = model.shownItems(in: group)
        Card(padding: DS.Space.md) {
            VStack(alignment: .leading, spacing: 0) {
                header(items)
                if let note = note(count: items.count) {
                    Text(note)
                        .font(.dsCaption)
                        .foregroundStyle(.dsTextTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.leading, GitCleanupMetrics.itemIndent)
                        .padding(.top, DS.Space.xxs)
                }
                ForEach(items) { item in
                    GitCleanupRow(model: model, item: item)
                        .padding(.leading, GitCleanupMetrics.itemIndent)
                }
            }
        }
    }

    private func header(_ items: [GitCleanupItem]) -> some View {
        let included = items.filter(model.isIncluded).count
        let value: GitCheckbox.Value = included == 0 ? .off : included == items.count ? .on : .mixed
        return HStack(spacing: DS.Space.md) {
            if model.phase == .review {
                GitCheckbox(value: value, label: model.headline(of: group)) {
                    model.setGroup(group, included: value != .on)
                }
            }
            Text(model.headline(of: group))
                .font(.dsCalloutSemibold)
                .foregroundStyle(included == 0 && model.phase == .review ? .dsTextTertiary : .dsTextPrimary)
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: DS.Space.md)
            if included == 0, model.phase == .review {
                Text("Not included")
                    .font(.dsCaption)
                    .foregroundStyle(.dsTextTertiary)
            }
        }
        .frame(minHeight: DS.Size.controlXS)
    }

    /// What the group means, where it isn't obvious.
    private func note(count: Int) -> String? {
        switch group {
        case .worktrees:
            "Archived the usual way: teardown scripts run, uncommitted work is saved as a checkpoint, and Unarchive brings each back."
        case .branches:
            "Native keeps each one's commit, so Undo can bring it back."
        case .staleRecords where count == 1:
            "Its folder was deleted outside Native; git still lists it."
        case .staleRecords:
            "Their folders were deleted outside Native; git still lists them."
        case .leftoverFolders:
            "Folders in Native's worktree location that git no longer knows about."
        case .otherBranches where count == 1:
            "Not made by Native, so it's left alone unless you include it."
        case .otherBranches:
            "Not made by Native, so they're left alone unless you include them."
        }
    }
}

#if DEBUG
#Preview("Cleanup group") {
    let app = AppModel.preview()
    let model = GitCleanupModel(
        project: app.previewProject() ?? Project(url: URL(filePath: "/")),
        services: GitPreviewFixtures.cleanupServices(app))
    model.phase = .review
    return DSPreviewPair {
        // Before the scan has found anything for the group: its header and what it would do.
        GitCleanupGroupSection(model: model, group: .worktrees)
            .frame(width: GitCleanupMetrics.sheetWidth - DS.Space.xxl)
    }
}
#endif
