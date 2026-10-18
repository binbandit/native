import ACP
import AppKit
import NativeAutomation
import NativeCommands
import SwiftUI

@main
struct NativeApp: App {
    @State private var model: AppModel
    @State private var git: GitStore
    @State private var gitHub: GitHubModel
    /// Held here because AppModel keeps its provider weakly.
    @State private var taskWorkspaces: GitTaskWorkspaceProvider
    @State private var iconPreferences = AppIconPreferences()
    /// `-nativeDate yyyy-MM-dd` previews another day's celebrations on the icon and Home.
    @State private var celebrations: CelebrationCenter
    /// Settings takes over the main window, as in the reference app, rather than opening one of its own.
    @State private var settings: SettingsPresentation
    @State private var terminals: TerminalStore
    @State private var keepAwake: KeepAwakeController
    @State private var statusBar: StatusBarRegistry
    /// One connection to this build's background host, shared by the main window and Durable Sessions.
    @State private var durableHost = DurableHost()
    @State private var updates: UpdateController
    @State private var whatsNew: WhatsNewCenter
    /// ⌘K, over the main window (docs/commands.md).
    @State private var palette: CommandPalette

    init() {
        LaunchMetrics.mark(.appInit)
        // Git and GitHub run with the login-shell environment the agents get.
        let model = AppModel()
        _model = State(initialValue: model)
        let git = GitStore { await model.shellEnvironment() }
        let gitHub = GitHubModel { await model.shellEnvironment(refresh: $0) }
        _git = State(initialValue: git)
        _gitHub = State(initialValue: gitHub)
        // New tasks get a worktree or branch as the Git settings say.
        let taskWorkspaces = GitTaskWorkspaceProvider(git: git, gitHub: gitHub)
        _taskWorkspaces = State(initialValue: taskWorkspaces)
        model.taskWorkspaces = taskWorkspaces
        // Agents are child processes; ending them with the app keeps them from outliving it.
        NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification, object: nil, queue: .main
        ) { _ in
            MainActor.assumeIsolated { model.stopAgents() }
        }
        GitAutomationWiring.connect(git, to: BuiltInPlugins.automation.center.automations)
        let settings = SettingsPresentation()
        _settings = State(initialValue: settings)
        let keepAwake = KeepAwakeController()
        _keepAwake = State(initialValue: keepAwake)
        let statusBar = AmbientWiring.statusBar(model: model, keepAwake: keepAwake, settings: settings)
        _statusBar = State(initialValue: statusBar)
        let celebrations = CelebrationCenter(now: HomeDateOverride.now)
        _celebrations = State(initialValue: celebrations)
        let terminals = TerminalStore()
        _terminals = State(initialValue: terminals)
        let updates = UpdateController()
        _updates = State(initialValue: updates)
        let whatsNew = WhatsNewCenter()
        _whatsNew = State(initialValue: whatsNew)
        // Every command, before the menu bar first draws.
        let palette = CommandPalette()
        _palette = State(initialValue: palette)
        CommandsWiring.connect(
            CommandRegistry.shared, palette: palette,
            features: .init(
                model: model, settings: settings, terminals: terminals, keepAwake: keepAwake, statusBar: statusBar,
                celebrations: celebrations, updates: updates, whatsNew: whatsNew))
    }

    var body: some Scene {
        Window("Native", id: "main") {
            RootView()
                .commandPalette(palette)
                .onAppear { LaunchMetrics.markOnScreen(.firstFrame) }
                .environment(CommandRegistry.shared)
                .environment(model)
                .environment(git)
                .environment(gitHub)
                .environment(BuiltInPlugins.automation.center)
                .environment(BuiltInPlugins.expeditions.center)
                .environment(terminals)
                .environment(durableHost)
                .environment(updates)
                .environment(whatsNew)
                .environment(settings)
                .environment(model.plugins)
                .environment(PolicyCenter.shared)
                .environment(TelemetryCenter.shared)
                .environment(git.settings)
                .environment(iconPreferences)
                .environment(celebrations)
                .environment(keepAwake)
                .environment(statusBar)
                .createPullRequestSheet(gitHub)
                .terminalCodeTheme(terminals)
                .appearancePreferences(plugins: model.plugins)
                .dsAccentPalette(themeID: iconPreferences.theme.rawValue)
                .task {
                    OrchestrationPlugin.connect(to: model)
                    MCPServersPlugin.connect(to: model) { BuiltInPlugins.usage.contextReports.reports }
                    SkillsPlugin.connect(to: model)
                    BuiltInPlugins.search.center.connect(to: model)
                    BuiltInPlugins.usage.connect(to: model)
                    BuiltInPlugins.automation.center.connect(to: model) { [git, gitHub] draft in
                        try await AutomationGitHubWiring.openPullRequest(draft, git: git, gitHub: gitHub)
                    }
                    BuiltInPlugins.automation.center.connectAutomations(
                        repository: { [gitHub] in await AutomationGitHubWiring.repository(of: $0, gitHub: gitHub) },
                        worktree: { [git] in try await AutomationGitHubWiring.worktree(for: $0, title: $1, git: git) },
                        pullRequests: { [gitHub] in
                            try await AutomationGitHubWiring.pullRequestSnapshots(gitHub: gitHub)
                        }
                    )
                    ExpeditionWiring.connect(BuiltInPlugins.expeditions.center, model: model, git: git, gitHub: gitHub)
                    AmbientWiring.connect(model: model, keepAwake: keepAwake)
                    DockBadgeWiring.connect(model: model, workflows: BuiltInPlugins.automation.center.workflows)
                    CelebrationsWiring.connect(
                        celebrations, plugins: model.plugins, icons: iconPreferences, settings: settings)
                    iconPreferences.start()
                    PolicyCenter.shared.start()
                    ExperimentsPolicyWiring.connect()
                    TelemetryCenter.shared.start { [model] in model.runtime($0)?.info?.version }
                    updates.restartContext = { [model] in model.updateRestartContext }
                    updates.start()
                    whatsNew.start()
                    await model.start()
                    LaunchMetrics.mark(.agentsReady)
                }
                .task { [gitHub] in
                    gitHub.openAsTask = { [model, git, weak gitHub] pullRequest in
                        guard let gitHub else { return }
                        try await GitHubGitWiring.openAsTask(pullRequest, app: model, git: git, gitHub: gitHub)
                    }
                    gitHub.askAgent = { [model, git, weak gitHub] prompt, destination in
                        guard let gitHub else { return }
                        try await GitHubAgentWiring.ask(
                            prompt, destination: destination, app: model, git: git, gitHub: gitHub)
                    }
                    gitHub.hasCurrentTask = { [model] in GitHubAgentWiring.currentTask(app: model) != nil }
                    await gitHub.keepFresh()
                }
                .task(id: model.plugins.enabledPlugins.map(\.manifest)) {
                    BuiltInPlugins.automation.center.reloadLibrary(from: model.plugins)
                    BuiltInPlugins.automation.center.automations.isEnabled = model.plugins.isEnabled(
                        BuiltInPlugins.automations.manifest.id)
                }
        }
        .defaultSize(width: 1120, height: 780)
        .commands {
            UpdateCommands(commands: CommandRegistry.shared)
            WhatsNewCommands(commands: CommandRegistry.shared)
            FileCommands(commands: CommandRegistry.shared)
            ViewCommands(commands: CommandRegistry.shared)
            SettingsCommands(settings: settings)
            GoCommands(commands: CommandRegistry.shared)
            SessionCommands(model: model, commands: CommandRegistry.shared)
            TerminalCommands(commands: CommandRegistry.shared)
            KeepAwakeCommands(controller: keepAwake, commands: CommandRegistry.shared)
            StatusBarCommands(registry: statusBar, commands: CommandRegistry.shared)
        }

        Window("Durable Sessions", id: HostPreviewWindow.id) {
            HostPreviewWindow()
                .environment(model)
                .environment(durableHost)
                .appearancePreferences(plugins: model.plugins)
                .dsAccentPalette(themeID: iconPreferences.theme.rawValue)
        }

    }
}

// The menus place commands; what each does, when it's available and its shortcut come from the
// registry (docs/commands.md). Default shortcuts are in docs/keyboard.md; change them there first.

private struct FileCommands: Commands {
    let commands: CommandRegistry

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            CommandMenuItem(.sessionNew, in: commands)
            CommandMenuItem(.sessionNewWithAgent, in: commands)
            CommandMenuItem(.expeditionNew, in: commands)
            CommandMenuItem(.projectOpen, in: commands)
            Divider()
            CommandMenuItem(.composerAttachFiles, in: commands)
        }
    }
}

private struct ViewCommands: Commands {
    let commands: CommandRegistry

    var body: some Commands {
        CommandGroup(replacing: .sidebar) {
            CommandMenuItem(.paletteShow, in: commands)
            Divider()
            CommandMenuItem(.viewToggleSidebar, in: commands)
            CommandMenuItem(.viewToggleSubagentInspector, in: commands)
            CommandMenuItem(.viewToggleChanges, in: commands)
            CommandMenuItem(.viewMCPServers, in: commands)
            CommandMenuItem(.viewNeedsYouFilter, in: commands)

            Divider()
            // Its own toggle, so the checkmark follows the preference; the shortcut is the registry's.
            FoldEarlierTurnsToggle()
                .keyboardShortcut(commands.keyboardShortcut(for: .transcriptFoldEarlierTurns))
            CommandMenuItem(.transcriptJumpToLatest, in: commands)

            Divider()
            CommandMenuItem(.celebrationRestore, in: commands)
            CommandMenuItem(.celebrationChoose, in: commands)
        }
    }
}

private struct SettingsCommands: Commands {
    let settings: SettingsPresentation
    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
        // ⌘, is macOS's standard Settings key, so it stays outside the registry.
        CommandGroup(replacing: .appSettings) {
            Button("Settings…") {
                // Settings lives in the main window, so bring the window back if it was closed.
                openWindow(id: "main")
                settings.toggle()
            }
            .keyboardShortcut(",")
        }
    }
}

private struct GoCommands: Commands {
    let commands: CommandRegistry

    var body: some Commands {
        CommandMenu("Go") {
            CommandMenuItem(.goBack, in: commands)
            CommandMenuItem(.goForward, in: commands)
            Divider()
            CommandMenuItem(.goPullRequests, in: commands)
            CommandMenuItem(.goExpeditions, in: commands)
            TranscriptSearchMenuItem(commands: commands)
        }
    }
}

private struct SessionCommands: Commands {
    let model: AppModel
    let commands: CommandRegistry
    @FocusedValue(\.activeSession) private var session

    var body: some Commands {
        CommandMenu("Session") {
            CommandMenuItem(.composerFocus, in: commands)
            CommandMenuItem(.sessionStop, in: commands)

            Divider()

            CommandMenuItem(.sessionNextPermissionMode, in: commands)
            CommandMenuItem(.sessionChooseModel, in: commands)

            Divider()

            // The visible task's folder (its worktree when it has one); disabled while no task is in
            // view (Home, Settings, Pull Requests).
            OpenInCommands(
                location: session.map {
                    OpenInLocation(folder: $0.cwd, host: model.currentProject?.host ?? .local)
                },
                commands: commands)

            Divider()

            CommandMenuItem(.goalEdit, in: commands)
            CommandMenuItem(.goalPauseOrResume, in: commands)
            CommandMenuItem(.goalClear, in: commands)
            CommandMenuItem(.workflowRun, in: commands)

            Divider()

            CommandMenuItem(.sessionRename, in: commands)
            CommandMenuItem(.sessionArchive, in: commands)
            CommandMenuItem(.sessionTogglePin, in: commands)
            CommandMenuItem(.sessionToggleUnread, in: commands)
            CommandMenuItem(.sidebarMoveUp, in: commands)
            CommandMenuItem(.sidebarMoveDown, in: commands)
            CommandMenuItem(.sessionNext, in: commands)
            CommandMenuItem(.sessionPrevious, in: commands)

            let listed = min(model.sessionList.count, CommandID.sessionSelectPositions.upperBound)
            if listed > 0 {
                Divider()
                ForEach(1...listed, id: \.self) { position in
                    CommandMenuItem(.sessionSelect(position), in: commands)
                }
            }
        }
    }
}
