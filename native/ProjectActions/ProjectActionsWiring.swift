import Exec
import Foundation
import NativeCommands
import ProjectActions
import TaskScripts
import Terminal

/// Connects project actions to the rest of the app at launch: the runner's environment, terminal
/// and settings, the repo trust the event scripts share, and the commands (Run Last, Stop, Edit,
/// and "Run: <name>" for every action name, kept in step as actions change).
@MainActor
enum ProjectActionsWiring {
    /// Whether the project's repo may supply commands, and how to let it: the same per-project
    /// switch, and the same organization policy, as the repo's event scripts (`docs/actions.md`).
    struct RepositoryTrust {
        var isAllowed: (URL) -> Bool
        var allow: (URL) -> Void
        /// False when the organization turns repo files off; the repo's actions are hidden then.
        var isAvailable: () -> Bool

        /// The repo scripts' own switch and policy.
        static func scripts(_ settings: TaskScriptSettings) -> Self {
            Self(
                isAllowed: { settings.allowsRepositoryScripts(forProjectAt: $0) },
                allow: { settings.setAllowsRepositoryScripts(true, forProjectAt: $0) },
                isAvailable: { settings.permissions.repositoryScripts })
        }
    }

    static func runner(
        model: AppModel, terminals: TerminalStore, settings: SettingsPresentation, trust: RepositoryTrust,
        commandRunner: (any CommandRunner)?
    ) -> ProjectActionRunner {
        let store = ProjectActionStore()
        store.allowsRepositoryActions = trust.isAvailable
        let runner = ProjectActionRunner(store: store, terminals: terminals)
        runner.hooks = ProjectActionRunner.Hooks(
            environment: { await model.shellEnvironment() },
            commandRunner: commandRunner,
            allowsRepository: trust.isAllowed,
            allowRepository: trust.allow,
            visibleSession: { model.selection.flatMap(model.session) },
            showTerminal: { key, jobKey in
                settings.close()
                model.selection = key
                guard let session = model.session(key) else { return }
                let panel = terminals.panel(for: session)
                panel.isVisible = true
                if let tab = panel.tabs.tab(forJob: jobKey) {
                    panel.select(tab.id)
                }
            },
            editActions: { project in settings.open(.project(project.id)) }
        )
        return runner
    }

    /// Where actions run for a task: its worktree, its terminal, its project's actions.
    static func target(for session: SessionModel, model: AppModel) -> ProjectActionTarget? {
        guard let id = model.catalog.lookup(session.key)?.project, let project = model.projects.project(id) else {
            return nil
        }
        return ProjectActionTarget(project: project, session: session)
    }

    /// Registers Run Last, Stop and Edit, and a "Run: <name>" command per action name, again
    /// whenever the actions change, dropping the ones whose action is gone.
    static func registerCommands(_ registry: CommandRegistry, runner: ProjectActionRunner, model: AppModel) {
        let target: @MainActor (CommandContext) -> ProjectActionTarget? = { context in
            context.session.flatMap { Self.target(for: $0, model: model) }
        }
        registry.register(NativeCommand.projectActions(runner, target: target))
        var registered: Set<CommandID> = []
        let sync = {
            let commands = NativeCommand.projectActionRuns(
                named: runner.store.actionNames, runner: runner, target: target)
            let ids = Set(commands.map(\.id))
            registry.unregister(registered.subtracting(ids))
            registry.register(commands)
            registered = ids
        }
        runner.store.actionsChanged = sync
        sync()
    }
}
