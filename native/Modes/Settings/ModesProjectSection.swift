import Modes
import SwiftUI

/// The modes a project shares, for its settings page: what's in its `.native/modes/` folder, the
/// files that couldn't be used and why, and how to share one when there are none.
///
///     ModesProjectSection(project: project)
struct ModesProjectSection: View {
    let project: Project

    @State private var editing: ModeEditor.Subject?
    private let library = ModeLibrary.shared

    var body: some View {
        let modes = library.projectModes(at: project.url)
        VStack(alignment: .leading, spacing: DS.Space.lg) {
            SettingsSubheading(
                "Modes",
                note:
                    "Shared with everyone who works on the repo, from \(ModeFile.folder) in the project's folder. Edit the files to change them."
            )
            if modes.modes.isEmpty, modes.problems.isEmpty {
                SettingsRowGroup {
                    SettingsRow(
                        "Share a mode with your team",
                        description: Text(
                            "Save one as \(ModeFile.folder)/<name>.md and commit it: settings at the top, instructions below. Copy one of yours as a file from Settings ▸ Modes."
                        )
                    ) {
                        Button("Reload") { library.refresh(projectAt: project.url) }
                    }
                }
            } else {
                ProjectModesList(root: project.url) { editing = .copy($0) }
            }
        }
        .task(id: project.id) { library.refresh(projectAt: project.url) }
        .sheet(item: $editing) { subject in
            ModeEditor(subject: subject)
        }
    }
}
