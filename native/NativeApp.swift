import ACP
import AppKit
import Exec
import NativeAutomation
import NativeCommands
import SwiftUI

@main
struct NativeApp: App {
    @State private var model: AppModel
    @State private var git: GitStore
    @State private var gitHub: GitHubModel
    /// The user's and repositories' scripts that run around tasks (docs/scripts.md).
    @State private var taskScripts: TaskScriptCenter
    /// Private questions about pull requests, beside their pages.
    @State private var pullRequestQuestions = PullRequestAskCenter()
    /// Held here because AppModel keeps its provider weakly.
    @State private var taskWorkspaces: GitTaskWorkspaceProvider
    @State private var iconPreferences = AppIconPreferences()
    /// `-nativeDate yyyy-MM-dd` previews another day's celebrations on the icon and Home.
    @State private var celebrations: CelebrationCenter
    /// Settings takes over the main window rather than opening one of its own.
    @State private var settings: SettingsPresentation
    @State private var terminals: TerminalStore
    /// Each project's quick actions (Test, Install…) and their runs (docs/actions.md).
    @State private var projectActions: ProjectActionRunner
    @State private var keepAwake: KeepAwakeController
    @State private var statusBar: StatusBarRegistry
    /// The keyboard shortcuts sheet: Help ▸ Keyboard Shortcuts and the status bar's "?".
    @State private var shortcutsHelp: KeyboardShortcutsHelp
    /// This build's background host: where agents run, and the connection to it (docs/durability.md).
    @State private var durableHost: DurableHost
    /// Holds a quit while the host stops, for Quit Native and Stop Agents.
    @NSApplicationDelegateAdaptor private var quitDelegate: HostQuitDelegate
    @State private var updates: UpdateController
    @State private var whatsNew: WhatsNewCenter
    /// ⌘K, over the main window (docs/commands.md).
    @State private var palette: CommandPalette
    /// Open as Task: a pull request checked out in a worktree of its project, with a task there.
    @State private var pullRequestTasks: PullRequestTaskOpener
    /// Clean Up Merged: a project's merged task worktrees and branches, reviewed before they go.
    @State private var gitCleanup: GitCleanupCenter
    /// Light, dark or the system's, for the whole app.
    @State private var appearance: AppearanceModeController

    init() {
        LaunchMetrics.mark(.appInit)
        FramePacing.startIfRequested()
        // Before any window exists, so the first one opens in the user's appearance.
        let appearance = AppearanceModeController()
        _appearance = State(initialValue: appearance)
        // Git and GitHub run with the login-shell environment the agents get.
        let model = AppModel()
        _model = State(initialValue: model)
        let durableHost = DurableHost()
        _durableHost = State(initialValue: durableHost)
        let git = GitStore { await model.shellEnvironment() }
        let gitHub = GitHubModel { await model.shellEnvironment(refresh: $0) }
        _git = State(initialValue: git)
        _gitHub = State(initialValue: gitHub)
        SessionToolsWiring.registerBuiltIns(.shared, git: git, gitHub: gitHub)
        let taskScripts = TaskScriptCenter(settings: TaskScriptSettings(), runner: LocalCommandRunner())
        _taskScripts = State(initialValue: taskScripts)
        TaskScriptsWiring.connect(taskScripts, model: model, git: git)
        // New tasks get a worktree or branch as the Git settings say.
        let taskWorkspaces = GitTaskWorkspaceProvider(git: git, gitHub: gitHub, scripts: taskScripts)
        _taskWorkspaces = State(initialValue: taskWorkspaces)
        model.taskWorkspaces = taskWorkspaces
        // A paired host's tasks get theirs there; this Mac's are unchanged.
        RemoteHostsWiring.connect(model: model, local: taskWorkspaces, git: git, gitHub: gitHub)
        // Agents are child processes; ending them with the app keeps them from outliving it. New
        // sessions still without a message keep their drafts for the next launch.
        NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification, object: nil, queue: .main
        ) { _ in
            MainActor.assumeIsolated {
                model.keepUnsentDrafts()
                model.stopAgents()
            }
        }
        GitAutomationWiring.connect(git, to: BuiltInPlugins.automation.center.automations)
        GitTurnWiring.connect(git, to: model)
        let settings = SettingsPresentation()
        _settings = State(initialValue: settings)
        let keepAwake = KeepAwakeController()
        _keepAwake = State(initialValue: keepAwake)
        let shortcutsHelp = KeyboardShortcutsHelp()
        _shortcutsHelp = State(initialValue: shortcutsHelp)
        let statusBar = AmbientWiring.statusBar(
            model: model, keepAwake: keepAwake, settings: settings, shortcutsHelp: shortcutsHelp)
        _statusBar = State(initialValue: statusBar)
        statusBar.register(HostConnectionStatusItem(host: durableHost))
        statusBar.register(
            TaskScriptsStatusItem(center: taskScripts, folder: { model.selection.flatMap(model.session)?.cwd }) {
                settings.open(.scripts)
            })
        let celebrations = CelebrationCenter(now: HomeDateOverride.now)
        _celebrations = State(initialValue: celebrations)
        let terminals = TerminalStore()
        _terminals = State(initialValue: terminals)
        // Repo actions share the repo scripts' per-project switch and policy.
        let projectActions = ProjectActionsWiring.runner(
            model: model, terminals: terminals, settings: settings, trust: .scripts(taskScripts.settings),
            commandRunner: LocalCommandRunner())
        _projectActions = State(initialValue: projectActions)
        let updates = UpdateController()
        _updates = State(initialValue: updates)
        let whatsNew = WhatsNewCenter()
        _whatsNew = State(initialValue: whatsNew)
        // Every command, before the menu bar first draws.
        let palette = CommandPalette()
        _palette = State(initialValue: palette)
        let pullRequestTasks = PullRequestTaskOpener(
            checkout: PullRequestTaskCheckout(app: model, git: git, gitHub: gitHub))
        _pullRequestTasks = State(initialValue: pullRequestTasks)
        gitHub.openAsTask = { pullRequestTasks.open($0) }
        let gitCleanup = GitCleanupWiring.center(app: model, git: git, gitHub: gitHub)
        _gitCleanup = State(initialValue: gitCleanup)
        gitHub.linkedPullRequest = { [git] in await GitHubGitWiring.linkedPullRequest(for: $0, git: git) }
        CommandsWiring.connect(
            CommandRegistry.shared, palette: palette,
            features: .init(
                model: model, settings: settings, terminals: terminals, keepAwake: keepAwake, statusBar: statusBar,
                celebrations: celebrations, updates: updates, whatsNew: whatsNew, appearance: appearance,
                pullRequestTasks: pullRequestTasks, shortcutsHelp: shortcutsHelp, gitCleanup: gitCleanup,
                projectActions: projectActions, durableHost: durableHost, git: git, gitHub: gitHub))
    }

    var body: some Scene {
        Window("Native", id: "main") {
            RootView()
                .commandPalette(palette)
                .onAppear {
                    LaunchMetrics.markOnScreen(.firstFrame)
                    FirstFrame.shared.watch()
                }
                .performanceDriver(model)
                .environment(CommandRegistry.shared)
                .environment(model)
                .environment(git)
                .environment(gitHub)
                .environment(pullRequestQuestions)
                .environment(BuiltInPlugins.automation.center)
                .environment(BuiltInPlugins.expeditions.center)
                .environment(terminals)
                .environment(projectActions)
                .environment(durableHost)
                .environment(updates)
                .environment(whatsNew)
                .environment(settings)
                .environment(model.plugins)
                .environment(PolicyCenter.shared)
                .environment(TelemetryCenter.shared)
                .environment(git.settings)
                .environment(taskScripts)
                .environment(taskScripts.settings)
                .environment(iconPreferences)
                .environment(appearance)
                .environment(celebrations)
                .environment(keepAwake)
                .environment(statusBar)
                .createPullRequestSheet(gitHub)
                .pullRequestMergeSheet(gitHub)
                .keyboardShortcutsSheet(shortcutsHelp)
                .pullRequestTaskSheet(pullRequestTasks, app: model, gitHub: gitHub)
                .projectActionsPresentation(projectActions)
                .gitCleanupSheet(gitCleanup)
                .environment(gitCleanup)
                .terminalCodeTheme(terminals)
                .appearancePreferences(plugins: model.plugins)
                .dsAccentPalette(themeID: iconPreferences.theme.rawValue)
                .task {
                    OrchestrationPlugin.connect(to: model, updates: updates, durableHost: durableHost)
                    MCPServersPlugin.connect(to: model) { BuiltInPlugins.usage.contextReports.reports }
                    SkillsPlugin.connect(to: model)
                    BuiltInPlugins.search.center.connect(to: model)
                    BuiltInPlugins.usage.connect(to: model)
                    BuiltInPlugins.usage.hostNotifications.connect(to: model)
                    BuiltInPlugins.usage.hostNotifications.onHostAway = { [durableHost, model] summary, host, isLocal in
                        if isLocal {
                            durableHost.away = summary
                        } else {
                            model.hosts.host(host)?.away = summary
                        }
                    }
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
                    // Where agents run is decided before any session starts: the background host,
                    // a host that stops with the app, or the app itself.
                    quitDelegate.host = durableHost
                    durableHost.connectUpdates(updates)
                    if let client = await durableHost.launch() {
                        model.connectHost(client: client)
                        keepAwake.useHost(client)
                        await BuiltInPlugins.usage.hostNotifications.follow(client)
                        await HostTitlesWiring.connect(model, to: client)
                    }
                    await model.start()
                    LaunchMetrics.mark(.agentsReady)
                }
                .task { [gitHub] in
                    gitHub.askAgent = { [model, git, weak gitHub] prompt, destination in
                        guard let gitHub else { return }
                        try await GitHubAgentWiring.ask(
                            prompt, destination: destination, app: model, git: git, gitHub: gitHub)
                    }
                    gitHub.hasCurrentTask = { [model] in GitHubAgentWiring.currentTask(app: model) != nil }
                    PullRequestAskWiring.connect(pullRequestQuestions, app: model, gitHub: gitHub)
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
            NativeMenuBar(
                model: model, settings: settings, host: durableHost, projectActions: projectActions,
                keepAwake: keepAwake, statusBar: statusBar)
        }
    }
}
