import SwiftUI

/// The workbench's add menu uses the same project actions as the well's first-run chooser.
struct TaskWellWorkbenchActions: View {
    let session: SessionModel
    @Environment(AppModel.self) private var app

    var body: some View {
        if !app.device(of: session.key).isRemote,
            let target = ProjectActionsWiring.target(for: session, model: app)
        {
            ProjectActionsMenuContent(target: target)
        }
    }
}

#if DEBUG
#Preview("Well - Workbench action menu") {
    let app = AppModel.preview()
    return DSPreviewPair {
        if let project = app.previewProject() {
            Menu("Add to workbench", systemImage: "plus") {
                ProjectActionsMenuContent(target: ProjectActionTarget(project: project, session: nil))
            }
            .environment(
                ProjectActionRunner(
                    store: ProjectActionStore(defaults: PreviewUserDefaults()),
                    terminals: TerminalStore(
                        preferences: TerminalPreferences(defaults: PreviewUserDefaults()),
                        makeEngine: { .failure(.notBuilt) }))
            )
            .environment(SettingsPresentation())
        }
    }
}
#endif
