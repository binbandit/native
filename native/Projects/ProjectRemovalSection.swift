import SwiftUI

/// What archiving a task does in the project, and putting the project itself away: archiving it
/// (it comes back from Archived) or deleting it from Native, worded and confirmed as in the
/// sidebar. Neither touches its folder, and both can be undone.
struct ProjectRemovalSection: View {
    let project: Project

    @Environment(AppModel.self) private var model
    @Environment(GitSettings.self) private var git
    @Environment(SettingsPresentation.self) private var settings
    @Environment(\.undoManager) private var undoManager
    @State private var isConfirmingRemoval = false

    private var rows: ProjectSettingsRows { ProjectSettingsRows(project: project.id) }

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.lg) {
            SettingsSubheading("Archiving")
            SettingsRowGroup {
                SettingsRow(
                    id: rows.archive, "When a task is archived",
                    description: Text(
                        "Its worktree is put away either way, with a checkpoint of uncommitted work. A deleted branch's commits stay reachable, so restoring the task brings it back."
                    )
                ) {
                    SettingsSelect(
                        label: "When a task is archived", selection: deletesBranch,
                        options: [
                            .init(value: nil, title: "Default (\(Self.title(deletes: git.deletesBranchOnArchive)))"),
                            .init(value: false, title: Self.title(deletes: false)),
                            .init(value: true, title: Self.title(deletes: true)),
                        ],
                        width: SettingsMetrics.selectWidth + DS.Space.xxxl * 2)
                }
                SettingsRow(
                    "Archive project",
                    description: Text(
                        "Hides \(project.name) and its tasks from the sidebar. It comes back from Archived, with its settings."
                    )
                ) {
                    Button("Archive Project") {
                        settings.close()
                        model.archiveProject(project.id, undoManager: undoManager)
                    }
                }
            }
            SettingsSubheading("Delete from Native")
            SettingsRowGroup {
                SettingsRow(
                    id: rows.remove, "Delete \(project.name) from Native",
                    description: Text(
                        "Native forgets the project and removes the task worktrees it made. Its folder and everything in it stay where they are. You can undo for a few seconds."
                    )
                ) {
                    Button("Delete Project…", role: .destructive) { isConfirmingRemoval = true }
                }
            }
        }
        .projectDeletionConfirmation(project, isPresented: $isConfirmingRemoval)
    }

    private var deletesBranch: Binding<Bool?> {
        Binding(
            get: { git.overrides(forProjectAt: project.url).deletesBranchOnArchive },
            set: { value in
                var overrides = git.overrides(forProjectAt: project.url)
                overrides.deletesBranchOnArchive = value
                git.setOverrides(overrides, forProjectAt: project.url)
            })
    }

    private static func title(deletes: Bool) -> String {
        deletes ? "Delete its branch" : "Keep its branch"
    }
}
