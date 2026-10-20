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
        let pullRequestTasks: PullRequestTaskOpener
        let shortcutsHelp: KeyboardShortcutsHelp
        let gitCleanup: GitCleanupCenter
        let projectActions: ProjectActionRunner
        let durableHost: DurableHost
    }

    static func connect(_ registry: CommandRegistry, palette: CommandPalette, features: Features) {
        let model = features.model
        let settings = features.settings
        let terminals = features.terminals
        registry.register(
            [.palette(palette, stepsAsideWhen: { NativeCommand.terminalHasFocus(terminals, in: $0) })])
        registry.register(NativeCommand.newTasks(model: model))
        registry.register([.projectSettings(model: model, settings: settings)])
        registry.register([.pullRequestTasks(features.pullRequestTasks)])
        registry.register([.gitCleanUpMerged(features.gitCleanup, model: model)])
        registry.register(NativeCommand.expeditions(model: model))
        registry.register([
            .openInDefaultApp { context in
                context.session.map { OpenInLocation(folder: $0.cwd, host: model.currentProject?.host ?? .local) }
            }
        ])
        registry.register(NativeCommand.taskActions(model: model))
        registry.register(NativeCommand.sidebarSelection(model: model))
        registry.register(NativeCommand.navigation(model: model, settings: settings))
        registry.register([.searchShow])
        registry.register(NativeCommand.composer)
        registry.register(NativeCommand.clearConversation(model: model))
        registry.register(NativeCommand.automation(BuiltInPlugins.automation.center))
        registry.register(NativeCommand.windowView)
        registry.register(NativeCommand.appearance(features.appearance))
        registry.register([.gitChanges, .keepAwake(features.keepAwake), .statusBar(features.statusBar)])
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
                    (SettingsPane.builtIn(registry: model.plugins)
                        + AppSettingsPanes.all(
                            plugins: model.plugins, terminals: terminals, keepAwake: features.keepAwake,
                            projects: model.projects.all))
                        .sorted { ($0.group, $0.order) < ($1.group, $1.order) }
                }, settings: settings),
            .queryCommands(registry),
        ]
    }
}
