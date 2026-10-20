import Git
import SwiftUI

/// One proposed commit in the smart commit review: its message, its files, and the edits a plan
/// needs (reorder, merge into the one before, split files off, leave files out).
struct GitCommitGroupCard: View {
    let model: GitSmartCommitModel
    let group: CommitPlan.Group
    let number: Int

    var body: some View {
        Card(padding: DS.Space.md) {
            VStack(alignment: .leading, spacing: DS.Space.sm) {
                HStack(spacing: DS.Space.sm) {
                    Text("\(number)")
                        .font(.dsMonoCaption)
                        .foregroundStyle(.dsTextTertiary)
                        .frame(minWidth: DS.Size.rowLeading)
                    TextField(
                        "Commit subject",
                        text: Binding(get: { group.subject }, set: { model.setSubject($0, of: group.id) })
                    )
                    .textFieldStyle(.plain)
                    .font(.dsCalloutMedium)
                    .foregroundStyle(.dsTextPrimary)
                    menu
                }
                TextField(
                    "Body (optional)",
                    text: Binding(get: { group.body }, set: { model.setBody($0, of: group.id) }),
                    axis: .vertical
                )
                .textFieldStyle(.plain)
                .font(.dsBody)
                .foregroundStyle(.dsTextSecondary)
                .lineLimit(1...6)
                .padding(.leading, DS.Size.rowLeading + DS.Space.sm)
                SeparatorLine()
                ForEach(group.paths, id: \.self) { path in
                    row(path)
                }
            }
        }
    }

    private var menu: some View {
        Menu {
            Button("Move Up") { model.moveUp(group.id) }
                .disabled(number == 1)
            Button("Move Down") { model.moveDown(group.id) }
                .disabled(number == model.groups.count)
            Button("Merge into Previous Commit") { model.mergeIntoPrevious(group.id) }
                .disabled(number == 1)
            Divider()
            Button("Leave Out of the Commits", role: .destructive) { model.remove(group.id) }
        } label: {
            Image(systemName: "ellipsis")
                .frame(width: DS.Size.controlXS, height: DS.Size.controlXS)
                .contentShape(.rect)
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .foregroundStyle(.dsTextSecondary)
        .dsHitTarget(DS.Size.controlXS)
        .help("Commit Options")
        .accessibilityLabel("Options for commit \(number)")
    }

    private func row(_ path: String) -> some View {
        HStack(spacing: DS.Space.sm) {
            GitCheckbox(value: .on, label: "Include \(path)") { model.exclude(path) }
            GitPathLabel(path: path, font: .dsBody)
                .frame(maxWidth: .infinity, alignment: .leading)
            if let file = model.file(path) {
                DiffStatLabel(added: file.stats.additions, removed: file.stats.deletions)
                GitStatusGlyph(kind: file.kind)
            }
            GitMoveFileMenu(model: model, path: path, current: group.id)
        }
        .frame(minHeight: DS.Size.controlXS)
    }
}

#if DEBUG
#Preview("Commit group card") {
    let model = GitSmartCommitModel(repository: GitPreviewFixtures.model)
    DSPreviewPair {
        VStack(spacing: DS.Space.md) {
            ForEach(Array(GitPreviewFixtures.commitGroups.enumerated()), id: \.element.id) { index, group in
                GitCommitGroupCard(model: model, group: group, number: index + 1)
            }
        }
        .frame(width: 560)
    }
}
#endif
