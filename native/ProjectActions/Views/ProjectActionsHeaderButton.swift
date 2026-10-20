import NativeCommands
import ProjectActions
import SwiftUI

extension View {
    /// Adds the task's Run menu to the window header: the project's actions, run in this task's
    /// worktree (`docs/actions.md`).
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

/// The header's outlined Run menu. It says what's going on at a glance: the running action's name
/// beside a loader while one runs, and a red dot after the last run failed.
struct ProjectActionsHeaderButton: View {
    let target: ProjectActionTarget
    @Environment(ProjectActionRunner.self) private var runner
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        let running = runner.running(in: target)
        Menu {
            ProjectActionsMenuContent(target: target)
                // Menus only show item icons when the content asks for them.
                .labelStyle(.titleAndIcon)
        } label: {
            label(running: running)
        }
        .menuStyle(.button)
        .buttonStyle(.header(isOn: !running.isEmpty))
        .menuIndicator(.hidden)
        .fixedSize()
        .help(help(running: running))
        .accessibilityLabel("Run")
        .accessibilityValue(running.isEmpty ? "" : "\(running.map(\.name).formatted()) running")
        // The repo file and suggestions are read again when the task shows and when Native comes
        // back to the front, so an edit made elsewhere shows up.
        .task(id: target.project.id) { runner.store.refresh(target.project) }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { runner.store.refresh(target.project) }
        }
    }

    @ViewBuilder private func label(running: [ProjectAction]) -> some View {
        if let first = running.first {
            Label {
                Text(running.count == 1 ? first.name : "\(running.count) running")
            } icon: {
                DotGridLoader(pattern: .waiting)
                    .frame(width: DS.Size.statusGlyph, height: DS.Size.statusGlyph)
            }
        } else {
            Label {
                HStack(spacing: DS.Space.xs) {
                    Text("Run")
                    if lastRunFailed {
                        StatusDot(color: .dsDanger)
                    }
                }
            } icon: {
                Image(systemName: "play.fill")
            }
        }
    }

    private var lastRunFailed: Bool {
        guard let last = runner.store.lastRunAction(in: target.project) else { return false }
        return runner.state(of: last, in: target)?.hasFailed == true
    }

    private func help(running: [ProjectAction]) -> String {
        if !running.isEmpty {
            return "\(running.map(\.name).formatted()) running. Open the menu to stop."
        }
        let base = "Run one of \(target.project.name)'s actions in this task"
        guard let last = runner.store.lastRunAction(in: target.project),
            let shortcut = CommandRegistry.shared.shortcut(for: .projectActionsRunLast)
        else { return base }
        return "\(base). \(shortcut.displayString) runs \(last.name) again."
    }
}

#if NATIVE_PREVIEWS_WIP
#Preview("Run button") {
    let app = AppModel.preview()
    let project = app.previewProject() ?? Project(url: URL(filePath: "/Users/preview/Developer/native"))
    DSPreviewPair {
        ProjectActionsHeaderButton(target: ProjectActionTarget(project: project, session: nil))
    }
    .environment(app)
    .environment(SettingsPresentation())
    .environment(ProjectActionsPreviewFixtures.runner(for: project))
}
#endif
