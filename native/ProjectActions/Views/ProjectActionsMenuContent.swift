import ProjectActions
import SwiftUI

/// A project's actions as menu items: what's running (to stop), Run Last, the user's actions, the
/// repo's, a few suggestions to add or dismiss, and Edit Actions…. The header's Run menu and the
/// project's context menu both show it. Nothing here runs on its own: a suggestion only runs from
/// its own Add and Run.
struct ProjectActionsMenuContent: View {
    let target: ProjectActionTarget
    var showsRunLast = true
    var showsManagedExplanation = true
    @Environment(ProjectActionRunner.self) private var runner
    @Environment(SettingsPresentation.self) private var settings

    /// Suggestions past this many wait in the project's settings.
    private static let suggestionLimit = 5

    var body: some View {
        let store = runner.store
        let project = target.project
        let list = store.list(for: project)
        let running = runner.running(in: target)

        if !running.isEmpty {
            Section {
                ForEach(running) { action in
                    let isStopping = runner.state(of: action, in: target)?.isStopping == true
                    Button(isStopping ? "End \(action.name) Now" : "Stop \(action.name)", systemImage: "stop.fill") {
                        runner.stop(action, in: target)
                    }
                }
            }
        }
        if showsRunLast, let last = store.lastRunAction(in: project) {
            Button("Run Last: \(last.name)", systemImage: "arrow.clockwise") { runner.run(last, in: target) }
        }
        Section {
            ForEach(list.yours) { item($0) }
        }
        if (!showsRunLast || !showsManagedExplanation), list.isRepositoryOff, store.hasRepositoryFile(in: project) {
            Section("From the repo") {
                Button(
                    showsManagedExplanation ? "Off by your organization" : "Repository actions unavailable",
                    systemImage: "lock"
                ) {}
                .disabled(true)
            }
        } else if !list.fromRepository.isEmpty {
            Section("From the repo") {
                ForEach(list.fromRepository) { item($0) }
            }
        }
        if !list.suggestions.isEmpty {
            Section("Suggested") {
                ForEach(list.suggestions.prefix(Self.suggestionLimit)) { suggestion in
                    Menu {
                        Button("Add") { store.add(suggestion, to: project) }
                        Button("Add and Run") { runner.run(store.add(suggestion, to: project), in: target) }
                        Divider()
                        Button("Dismiss") { store.dismiss(suggestion, in: project) }
                    } label: {
                        Label("\(suggestion.name) · \(suggestion.command)", systemImage: suggestion.icon)
                    }
                }
            }
        }
        if list.all.isEmpty, list.suggestions.isEmpty {
            Text(list.hasScanned ? "No actions for \(project.name) yet" : "Looking for actions…")
        }
        Divider()
        Button(list.all.isEmpty ? "Add Action…" : "Edit Actions…", systemImage: "slider.horizontal.3") {
            if list.all.isEmpty {
                store.requestNewAction(in: project)
            }
            settings.open(.project(project.id))
        }
    }

    private func item(_ action: ProjectAction) -> some View {
        let state = runner.state(of: action, in: target)
        let title = state?.isRunning == true ? "\(action.name) · running" : action.name
        return Button(title, systemImage: action.icon ?? ProjectActionGlyph.fallback) { runner.run(action, in: target) }
    }
}

/// The glyph an action without one of its own shows.
enum ProjectActionGlyph {
    static let fallback = "terminal"
}

#if NATIVE_PREVIEWS_WIP
#Preview("Run menu") {
    let app = AppModel.preview()
    let project = app.previewProject() ?? Project(url: URL(filePath: "/Users/preview/Developer/native"))
    DSPreviewPair {
        HStack(spacing: DS.Space.lg) {
            Menu("Run") {
                ProjectActionsMenuContent(target: ProjectActionTarget(project: project, session: nil))
                    .labelStyle(.titleAndIcon)
            }
            .environment(ProjectActionsPreviewFixtures.runner(for: project))
            // A project with no actions yet.
            Menu("Run (none yet)") {
                ProjectActionsMenuContent(target: ProjectActionTarget(project: project, session: nil))
                    .labelStyle(.titleAndIcon)
            }
            .environment(ProjectActionsPreviewFixtures.runner(for: project, actions: []))
        }
        .fixedSize()
    }
    .environment(SettingsPresentation())
}
#endif
