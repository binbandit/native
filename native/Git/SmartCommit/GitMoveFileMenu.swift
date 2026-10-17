import Git
import SwiftUI

/// "Move to" for a file in the smart commit review: another commit, or a new one.
struct GitMoveFileMenu: View {
    let model: GitSmartCommitModel
    let path: String
    /// The commit the file is in; `nil` when it's left out.
    let current: CommitPlan.Group.ID?

    var body: some View {
        Menu {
            ForEach(Array(model.groups.enumerated()), id: \.element.id) { index, group in
                if group.id != current {
                    Button("\(index + 1). \(group.subject)") { model.move(path, to: group.id) }
                }
            }
            Divider()
            Button("New Commit") { model.move(path, to: nil) }
        } label: {
            Image(systemName: "arrow.turn.down.right")
                .frame(width: DS.Size.controlXS, height: DS.Size.controlXS)
                .contentShape(.rect)
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .foregroundStyle(.dsTextSecondary)
        .dsHitTarget(DS.Size.controlXS)
        .help("Move to Another Commit")
        .accessibilityLabel("Move \(path) to another commit")
    }
}
