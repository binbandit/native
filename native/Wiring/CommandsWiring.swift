import NativeCommands

/// Registers every built-in feature's commands and gives the command palette its sources, at
/// launch, before the menu bar first draws. Within a category, Settings lists commands in this
/// order. A new feature adds its commands here (one line), next to where it builds them.
@MainActor
enum CommandsWiring {
    struct Features {
        let model: AppModel
        let settings: SettingsPresentation
        let terminals: TerminalStore
        let keepAwake: KeepAwakeController
        let statusBar: StatusBarRegistry
        let celebrations: CelebrationCenter
        let updates: UpdateController
        let whatsNew: WhatsNewCenter
        let appearance: AppearanceModeController
        let tryOn: ThemeTryOnModel
        let pullRequestTasks: PullRequestTaskOpener
        let shortcutsHelp: KeyboardShortcutsHelp
        let gitCleanup: GitCleanupCenter
        let projectActions: ProjectActionRunner
        let durableHost: DurableHost
        let git: GitStore
        let gitHub: GitHubModel
    }

    static func connect(_ registry: CommandRegistry, palette: CommandPalette, features: Features) {
        let model = features.model
        let settings = features.settings
        CommandKnowledgeWiring.connect(model)
        registry.register(NativeCommand.commandKnowledge(settings: settings))
        let terminals = features.terminals
        registry.register(
            [.palette(palette, stepsAsideWhen: { NativeCommand.terminalHasFocus(terminals, in: $0) })])
        registry.register(NativeCommand.newTasks(model: model))
        registry.register(NativeCommand.coordinatorTasks(model: model))
        registry.register(NativeCommand.quickEntry(model: model))
        registry.register(NativeCommand.taskPairs(model: model))
        registry.register([.projectSettings(model: model, settings: settings), .projectRefresh(model: model)])
        registry.register([.pullRequestTasks(features.pullRequestTasks)])
        registry.register([.gitCleanUpMerged(features.gitCleanup, model: model)])
        registry.register(NativeCommand.expeditions(model: model))
        registry.register([
            .openInDefaultApp { context in
                context.session.map { OpenInLocation(folder: $0.cwd, host: model.currentProject?.host ?? .local) }
            }
        ])
        registry.register(NativeCommand.taskActions(model: model))
        let taskPullRequests = AppTaskPullRequests(model: model, git: features.git, gitHub: features.gitHub)
        registry.register([
            .taskPullRequest(features.gitHub) { context in
                context.session.flatMap { taskPullRequests.pullRequest(for: $0.key) }
            }
        ])
        registry.register(NativeCommand.sidebarSelection(model: model))
        registry.register(NativeCommand.taskPeek(model: model))
        registry.register(NativeCommand.navigation(model: model, settings: settings))
        registry.register([.searchShow])
        #if os(macOS)
        registry.register([.gitHubAccounts(settings: settings)])
        #endif
        // Try On takes ⌘. while it runs (docs/keyboard.md), so Stop steps aside rather than ending the turn.
        registry.register(
            NativeCommand.composer.map { command in
                command.id == .sessionStop ? command.stepsAside { _ in features.tryOn.isActive } : command
            })
        registry.register(NativeCommand.clearConversation(model: model))
        registry.register([.changeAgent(model: model)])
        registry.register(NativeCommand.automation(BuiltInPlugins.automation.center))
        registry.register(NativeCommand.windowView)
        registry.register(NativeCommand.appearance(features.appearance))
        registry.register([.themeTryOn(features.tryOn)])
        registry.register([.gitChanges, .keepAwake(features.keepAwake), .statusBar(features.statusBar)])
        registry.register(NativeCommand.sessionTools)
        registry.register(NativeCommand.taskWell)
        registry.register(NativeCommand.celebrations(features.celebrations, settings: settings))
        registry.register(NativeCommand.terminal(terminals))
        ProjectActionsWiring.registerCommands(registry, runner: features.projectActions, model: model)
        ModesWiring.connect(registry, model: model, settings: settings)
        #if os(macOS)
        registry.register([.checkForUpdates(features.updates, settings: settings)])
        registry.register([.quitAndStopAgents(features.durableHost)])
        #endif
        registry.register([.whatsNew(features.whatsNew), .keyboardShortcuts(features.shortcutsHelp)])
        registry.reportUnregisteredDefaults()

        palette.sources = [
            .commands(registry),
            .tasks(model: model, settings: settings),
            .projects(model: model, settings: settings),
            .settingsPages(
                {
                    SettingsPageMap.panes(
                        SettingsPane.builtIn(registry: model.plugins)
                            + AppSettingsPanes.all(
                                plugins: model.plugins, terminals: terminals, keepAwake: features.keepAwake,
                                projects: model.projects.all),
                        registry: model.plugins, plainly: SettingsPageMap.isEnabled)
                }, settings: settings),
            .queryCommands(registry),
        ]
    }
}
