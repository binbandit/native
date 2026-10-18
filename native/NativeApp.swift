import ACP
import AppKit
import NativeAutomation
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
    @State private var celebrations = CelebrationCenter(now: HomeDateOverride.now)
    /// Settings takes over the main window, as in the reference app, rather than opening one of its own.
    @State private var settings: SettingsPresentation
    @State private var terminals = TerminalStore()
    @State private var keepAwake: KeepAwakeController
    @State private var statusBar: StatusBarRegistry
    /// One connection to this build's background host, shared by the main window and Durable Sessions.
    @State private var durableHost = DurableHost()
    @State private var updates = UpdateController()
    @State private var whatsNew = WhatsNewCenter()

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
        _statusBar = State(initialValue: AmbientWiring.statusBar(model: model, keepAwake: keepAwake, settings: settings))
    }

    var body: some Scene {
        Window("Native", id: "main") {
            RootView()
                .onAppear { LaunchMetrics.markOnScreen(.firstFrame) }
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
                        try await GitHubAgentWiring.ask(prompt, destination: destination, app: model, git: git, gitHub: gitHub)
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
            UpdateCommands(controller: updates, settings: settings)
            WhatsNewCommands(center: whatsNew)
            FileCommands(model: model)
            ViewCommands(celebrations: celebrations, settings: settings)
            SettingsCommands(settings: settings)
            GoCommands(model: model, settings: settings)
            SessionCommands(model: model)
            TerminalCommands(store: terminals)
            KeepAwakeCommands(controller: keepAwake)
            StatusBarCommands(registry: statusBar)
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

// Every shortcut here is listed in `docs/keyboard.md`; change it there first.

private struct FileCommands: Commands {
    let model: AppModel
    @FocusedValue(\.activeSession) private var session

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("New Session") {
                Task { await model.newSession() }
            }
            .keyboardShortcut("n")
            // Never disabled otherwise: without a project or an agent, New Session says what's missing.
            .disabled(model.isCreatingSession)

            Button("New Session With…") {
                model.isChoosingAgent = true
            }
            .keyboardShortcut("n", modifiers: [.command, .option])
            .disabled(model.projects.all.isEmpty || model.agents.isEmpty)

            NewExpeditionMenuItem(model: model)

            Button("Open Folder…") {
                model.isAddingProject = true
            }
            .keyboardShortcut("o")

            Divider()

            Button("Attach Files…") {
                session?.isAttachmentPickerRequested = true
            }
            .keyboardShortcut("u")
            .disabled(session == nil || session?.acceptsPrompts == false || session?.phase == .disconnected)
        }
    }
}

private struct ViewCommands: Commands {
    let celebrations: CelebrationCenter
    let settings: SettingsPresentation
    @FocusedValue(\.sidebarVisibility) private var sidebarVisibility
    @FocusedValue(\.activeSession) private var session
    @FocusedValue(\.mcpServersPopover) private var mcpServersPopover
    @FocusedValue(\.sidebarNeedsYouFilter) private var needsYouFilter

    var body: some Commands {
        CommandGroup(replacing: .sidebar) {
            Button(sidebarVisibility?.wrappedValue == .detailOnly ? "Show Sidebar" : "Hide Sidebar") {
                guard let sidebarVisibility else { return }
                withAnimation {
                    sidebarVisibility.wrappedValue = sidebarVisibility.wrappedValue == .detailOnly ? .all : .detailOnly
                }
            }
            .keyboardShortcut("s", modifiers: [.command, .control])
            .disabled(sidebarVisibility == nil)

            Button("Toggle Subagent Inspector") {
                session?.isSubagentInspectorToggleRequested = true
            }
            .keyboardShortcut("i", modifiers: [.command, .option])
            .disabled(session?.state.subagents.isEmpty ?? true)

            GitChangesMenuItem()

            Button("Show MCP Servers") {
                mcpServersPopover?.wrappedValue.toggle()
            }
            .keyboardShortcut("m", modifiers: [.command, .control])
            .disabled(mcpServersPopover == nil)

            Toggle(
                "Show Only Tasks That Need You",
                isOn: Binding(
                    get: { needsYouFilter?.wrappedValue ?? false },
                    set: { needsYouFilter?.wrappedValue = $0 }
                )
            )
            .keyboardShortcut("j", modifiers: [.command, .option])
            .disabled(needsYouFilter == nil)

            Divider()
            FoldEarlierTurnsToggle()
            JumpToLatestMenuItem()

            Divider()
            CelebrationMenuItems(center: celebrations, settings: settings)
        }
    }
}

private struct SettingsCommands: Commands {
    let settings: SettingsPresentation
    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
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
    let model: AppModel
    let settings: SettingsPresentation

    var body: some Commands {
        CommandMenu("Go") {
            // In Settings, Back returns to where you were, like its Back button and Escape.
            Button("Back") {
                if settings.isShown {
                    settings.close()
                } else {
                    model.goBack()
                }
            }
            .keyboardShortcut("[")
            .disabled(!settings.isShown && !model.canGoBack)

            Button("Forward") {
                model.goForward()
            }
            .keyboardShortcut("]")
            .disabled(settings.isShown || !model.canGoForward)

            Divider()
            PullRequestsMenuItem()
            ExpeditionsMenuItem()
            TranscriptSearchMenuItem()
        }
    }
}

private struct SessionCommands: Commands {
    let model: AppModel
    @FocusedValue(\.activeSession) private var session
    /// The main window's undo manager, so ⌘Z takes back what these commands do. Read from AppKit
    /// because a focused value isn't there when the window's focus is outside SwiftUI's reach.
    private var undoManager: UndoManager? {
        (NSApp.keyWindow ?? NSApp.mainWindow)?.undoManager
    }

    var body: some Commands {
        CommandMenu("Session") {
            Button("Focus Composer") {
                session?.wantsComposerFocus = true
            }
            .keyboardShortcut("l")
            .disabled(session == nil || session?.isSubagent == true)

            Button("Stop") {
                Task { await session?.cancel() }
            }
            .keyboardShortcut(".")
            .disabled(session?.canCancel != true)

            Divider()

            Button("Next Permission Mode") {
                guard let session else { return }
                Task { await nextPermissionMode(of: session) }
            }
            .keyboardShortcut("m", modifiers: [.command, .shift])
            .disabled(session.map { ComposerSettings($0.configOptions).autonomy == nil } ?? true)

            Button("Choose Model…") {
                session?.isModelPickerRequested = true
            }
            .keyboardShortcut("e", modifiers: [.command, .shift])
            .disabled(session.map { ComposerSettings($0.configOptions).model == nil } ?? true)

            Divider()

            // The visible task's folder (its worktree when it has one); disabled while no task is in
            // view (Home, Settings, Pull Requests).
            OpenInCommands(
                location: session.map {
                    OpenInLocation(folder: $0.cwd, host: model.currentProject?.host ?? .local)
                })

            Divider()

            AutomationMenuItems(center: BuiltInPlugins.automation.center, session: session)

            Divider()

            Button("Rename Session…") {
                model.renaming = model.selection
            }
            .disabled(model.selection == nil)

            Button("Archive Task") {
                guard let key = model.selection else { return }
                Task { await model.archiveSession(key, undoManager: undoManager) }
            }
            .keyboardShortcut("a", modifiers: [.command, .shift])
            .disabled(model.selection == nil)

            Button(model.selection.map(model.isPinned) == true ? "Unpin Task" : "Pin Task") {
                guard let key = model.selection else { return }
                model.setPinned(key, !model.isPinned(key), undoManager: undoManager)
            }
            .disabled(model.selection == nil)

            Button(model.selection.map(model.isUnread) == true ? "Mark as Read" : "Mark as Unread") {
                guard let key = model.selection else { return }
                model.setUnread(key, !model.isUnread(key))
            }
            .disabled(model.selection == nil)

            // From the model rather than the sidebar's focused value, so they work wherever focus is
            // and while the sidebar is hidden.
            Button("Move Up") {
                model.sidebarMoveTarget.map { model.move($0, .up) }
            }
            .keyboardShortcut(.upArrow, modifiers: [.command, .option])
            .disabled(model.sidebarMoveTarget.map { model.canMove($0, .up) } != true)

            Button("Move Down") {
                model.sidebarMoveTarget.map { model.move($0, .down) }
            }
            .keyboardShortcut(.downArrow, modifiers: [.command, .option])
            .disabled(model.sidebarMoveTarget.map { model.canMove($0, .down) } != true)

            Button("Next Session") {
                model.selectSession(offset: 1)
            }
            .keyboardShortcut(.tab, modifiers: .control)
            .disabled(model.sessionList.isEmpty)

            Button("Previous Session") {
                model.selectSession(offset: -1)
            }
            .keyboardShortcut(.tab, modifiers: [.control, .shift])
            .disabled(model.sessionList.isEmpty)

            let shortcuts = Array(model.sessionList.prefix(9).enumerated())
            if !shortcuts.isEmpty {
                Divider()
                ForEach(shortcuts, id: \.element.id) { index, listed in
                    Button(model.title(for: listed)) {
                        model.selection = listed.id
                    }
                    .keyboardShortcut(KeyEquivalent(Character("\(index + 1)")))
                }
            }
        }
    }

    /// Moves the permission mode one step up the autonomy scale, wrapping around; Plan Mode isn't a step.
    private func nextPermissionMode(of session: SessionModel) async {
        guard let change = ComposerSettings(session.state.configOptions).nextAutonomy else { return }
        await session.setConfigOption(change.setting.option, to: change.value)
    }
}
