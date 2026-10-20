#if NATIVE_PREVIEWS_WIP
import Foundation
import ProjectActions
import Terminal

/// Project actions for previews: a runner over in-memory storage with no terminal engine started, so
/// nothing an action would run ever does.
enum ProjectActionsPreviewFixtures {
    static let actions = [
        ProjectAction(name: "Install", command: "bun install", icon: "shippingbox", presentation: .background),
        ProjectAction(name: "Dev Server", command: "bun run dev", icon: "play.circle"),
        ProjectAction(
            name: "Test", command: "swift test --package-path Packages/ACP", icon: "checkmark.seal",
            directory: ProjectAction.Directory(base: .worktree, path: "Packages/ACP")),
        ProjectAction(
            name: "Format", command: "swift format format -i --recursive native Packages", icon: "wand.and.stars",
            presentation: .background),
    ]

    /// A runner whose project has `actions` of the user's own.
    static func runner(for project: Project?, actions: [ProjectAction] = actions) -> ProjectActionRunner {
        let defaults = PreviewUserDefaults()
        let store = ProjectActionStore(defaults: defaults)
        if let project {
            for action in actions {
                store.add(action, to: project)
            }
        }
        return ProjectActionRunner(
            store: store, terminals: TerminalStore(preferences: TerminalPreferences(defaults: defaults)))
    }

    static func backgroundRun(_ result: ProjectActionBackgroundRun.Result?) -> ProjectActionBackgroundRun {
        var run = ProjectActionBackgroundRun(
            action: actions[3], directory: URL(filePath: "/Users/preview/Developer/native"),
            startedAt: .now.addingTimeInterval(-14))
        run.result = result
        return run
    }

    static let failedRun = backgroundRun(.finished(.exited(status: 1, duration: .seconds(2)), output: formatOutput))
    static let silentRun = backgroundRun(.finished(.exited(status: 0, duration: .seconds(14)), output: ""))
    static let unstartedRun = backgroundRun(.failedToStart("The folder Packages/ACP isn't in this worktree."))

    static let formatOutput = """
        native/Views/Composer/ComposerView.swift:212:121: error: [LineLength] line is too long
        native/Views/Sidebar/SessionRow.swift:88:5: warning: [OrderedImports] sort import statements lexicographically
        2 files need formatting.
        """
}
#endif
