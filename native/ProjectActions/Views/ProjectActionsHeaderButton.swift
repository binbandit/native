import NativeCommands
import ProjectActions
import SwiftUI

extension View {
    /// Adds the task's Run control, using the project's actions in this task's worktree.
    func projectActions(for session: SessionModel) -> some View {
        modifier(ProjectActionsHeaderModifier(session: session))
    }
}

private struct ProjectActionsHeaderModifier: ViewModifier {
    let session: SessionModel
    @Environment(AppModel.self) private var model

    func body(content: Content) -> some View {
        content.toolbar {
            if let target = ProjectActionsWiring.target(for: session, model: model) {
                ToolbarItem {
                    ProjectActionsHeaderButton(target: target)
                }
                .sharedBackgroundVisibility(.hidden)
            }
        }
    }
}

/// The named action runs with one click; the separate chevron keeps the project's action menu.
struct ProjectActionsHeaderButton: View {
    let target: ProjectActionTarget
    @Environment(AppModel.self) private var model
    @Environment(ProjectActionRunner.self) private var runner
    @Environment(\.scenePhase) private var scenePhase
    @State private var finishedAction: ProjectAction.ID?

    var body: some View {
        let action = runner.headerAction(in: target)
        let state = action.flatMap { runner.state(of: $0, in: target) }
        let running = runner.running(in: target)
        let removed = target.session.map { model.removedWorkspaces[$0.key] != nil } ?? false
        let completion = Completion(folder: target.worktree, action: action?.id, state: state)
        ProjectActionsRunControl(
            name: action?.name, state: state, runningNames: running.map(\.name),
            showsFinished: action != nil && finishedAction == action?.id, isFolderRemoved: removed,
            projectName: target.project.name,
            shortcut: CommandRegistry.shared.shortcut(for: .projectActionsRunLast)?.displayString,
            perform: {
                guard let action, !removed else { return }
                if state?.isRunning == true {
                    runner.stop(action, in: target)
                } else {
                    runner.run(action, in: target)
                }
            }
        ) {
            ProjectActionsMenuContent(target: target, showsRunLast: false)
                .labelStyle(.titleAndIcon)
        }
        .onChange(of: completion) { old, new in
            if old.folder == new.folder, old.action == new.action, old.state?.isRunning == true,
                case .finished(.exited(status: 0, _)) = new.state
            {
                finishedAction = new.action
            } else {
                finishedAction = nil
            }
        }
        .task(id: finishedAction) {
            guard finishedAction != nil else { return }
            do {
                try await Task.sleep(for: DS.RunControl.finishedDuration)
                finishedAction = nil
            } catch {
                // A new run or another task owns the control now.
            }
        }
        .task(id: target.project.id) { runner.store.refresh(target.project) }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { runner.store.refresh(target.project) }
        }
    }

    private struct Completion: Equatable {
        let folder: URL
        let action: ProjectAction.ID?
        let state: ProjectActionRunState?
    }
}

#if DEBUG
#Preview("Run - Header states") { ProjectActionsRunPreview() }
#endif
