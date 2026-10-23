import ACP
import NativeAutomation
import NativeHostClient
import NativeHostProtocol
import SwiftUI
import Undo
import UniformTypeIdentifiers

struct RootView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.undoManager) private var undoManager
    @Environment(\.releaseChannel) private var releaseChannel
    @State private var columnVisibility = NavigationSplitViewVisibility.all
    /// The sidebar's width as the user left it. Settings replaces the split view, and a new one opens
    /// at its ideal width, so this is the ideal.
    @State private var sidebarWidth = RootSidebarWidth()
    /// Room for a session's inspector, which the sidebar makes rather than the window growing.
    @State private var inspectorRoom = SidebarInspectorRoom()
    /// Where each session's transcript was left and what was opened in it, so switching back to a
    /// session shows the same place.
    @State private var transcriptMemory = SessionTranscriptMemory()
    @State private var undoToast: UndoToastItem?
    @State private var showsPullRequests = false
    @Environment(GitHubModel.self) private var gitHub
    @Environment(GitStore.self) private var git
    @Environment(AutomationCenter.self) private var automation
    /// Workflows or Automations, when one of them has the detail column.
    @State private var automationPage: AutomationPage?
    /// The run open on the Workflows page, if any.
    @State private var workflowPath: [WorkflowRun.ID] = []
    @Environment(ExpeditionCenter.self) private var expeditions
    @Environment(SettingsPresentation.self) private var settings
    @Environment(TerminalStore.self) private var terminals
    @Environment(KeepAwakeController.self) private var keepAwake
    @Environment(StatusBarRegistry.self) private var statusBar
    /// The background host and the updater, once the app provides them (docs/durability.md).
    @Environment(DurableHost.self) private var durableHost: DurableHost?
    @Environment(UpdateController.self) private var updates: UpdateController?
    @Environment(WhatsNewCenter.self) private var whatsNew

    var body: some View {
        @Bindable var model = model
        @Bindable var automation = automation
        // The status bar is part of the layout, under everything, so nothing ends up beneath it.
        VStack(spacing: 0) {
            contentWithUndo
            StatusBar(registry: statusBar)
        }
        .addHostPresentation(hosts: model.hosts)
        // After an update with highlights, once nothing waits on the user.
        .whatsNewSheet(whatsNew, blocked: model.hasWorkNeedingUser)
        // Asked once, after real use, and never while an agent works (docs/enterprise.md).
        .telemetryConsentPrompt(isTurnRunning: isAnyTurnRunning)
        .focusedSceneValue(\.sidebarVisibility, $columnVisibility)
        .focusedSceneValue(\.showsPullRequests, $showsPullRequests)
        // The pull requests page and a session take turns in the detail column.
        .onChange(of: showsPullRequests) { _, shows in
            if shows {
                model.selection = nil
                automationPage = nil
                expeditions.isPageShown = false
            }
        }
        .onChange(of: automationPage) { _, page in
            if page != nil {
                model.selection = nil
                showsPullRequests = false
                expeditions.isPageShown = false
            }
        }
        .onChange(of: model.selection) { _, key in
            if key != nil {
                showsPullRequests = false
                automationPage = nil
                expeditions.isPageShown = false
            }
        }
        .onChange(of: expeditions.isPageShown) { _, shows in
            if shows {
                model.selection = nil
                showsPullRequests = false
                automationPage = nil
            }
        }
        .changeAgentPresentation()
        .newExpeditionSheet()
        .sheet(isPresented: $automation.isWorkflowPickerRequested) {
            WorkflowPickerSheet(cwd: model.currentProject?.url, onAddProject: { model.isAddingProject = true }) {
                run in
                automationPage = .workflows
                workflowPath = [run]
            }
        }
        .task(id: model.selection) {
            if let key = model.selection {
                await model.loadSession(key)
            }
        }
        .sheet(item: $model.terminalSignIn) { request in
            AgentTerminalSignInSheet(request: request) { await model.finishTerminalSignIn($0) }
        }
        .sheet(isPresented: $model.isAddingAgent) {
            AddAgentSheet(agents: model.agentsToAdd, summaries: model.plugins.descriptions) {
                await model.checkForAgents()
            }
        }
        // Every agent with its state; a system dialog shows only three choices.
        .agentPicker(isPresented: $model.isChoosingAgent)
        .fileImporter(isPresented: $model.isAddingProject, allowedContentTypes: [.folder]) { result in
            if case .success(let url) = result {
                Task { await model.addProject(url) }
            }
        }
        .actionFailureAlert()
        .alert(
            "Sign In to \(signInAgent?.agent.displayName ?? "")",
            isPresented: Binding(get: { model.signInPrompt != nil }, set: { if !$0 { model.signInPrompt = nil } }),
            presenting: signInAgent
        ) { runtime in
            ForEach(runtime.authMethods, id: \.id) { method in
                Button(method.name) {
                    Task {
                        if await model.signIn(to: runtime.agent.id, with: method, thenStartSession: true) {
                            await model.newSession(with: runtime.agent.id)
                        }
                    }
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: { runtime in
            Text("\(runtime.agent.displayName) needs you to sign in before it can start a task.")
        }
    }

    /// Whether any agent is in a turn, so the telemetry question waits for a calm moment.
    private var isAnyTurnRunning: Bool {
        model.agents.contains { runtime in
            model.sessions.open(of: runtime.agent.id).contains { $0.phase == .prompting }
        }
    }

    /// Keep toast observation off the root's sheet chain so the type checker can finish it.
    private var contentWithUndo: some View {
        content
            .transcriptSearchPanel()
            // Opening a pull request (from a badge, a link or the list) shows its page there,
            // even the one the pane already held while a task had the column.
            .onChange(of: gitHub.pageRequests, initial: true) {
                if gitHub.presentedPullRequest != nil { showsPullRequests = true }
            }
            // Over the content, so the toast clears the status bar.
            .undoToast($undoToast)
            .onChange(of: undoManager, initial: true) { model.undoHistory.track(undoManager) }
            // Undone by ⌘Z or redone by ⇧⌘Z, it leaves the toast or comes back to it.
            .onChange(of: model.offeredUndo?.id) {
                undoToast = model.offeredUndo.map { action in
                    UndoToastItem(action.message, undoesWithCommandZ: model.undoHistory.willUndo(action)) {
                        action.undo()
                    }
                }
            }
            .onChange(of: model.offeredUndo?.message) {
                undoToast = model.offeredUndo.map { action in
                    UndoToastItem(action.message, undoesWithCommandZ: model.undoHistory.willUndo(action)) {
                        action.undo()
                    }
                }
            }
            .onChange(of: model.offeredUndo.map { model.undoHistory.willUndo($0) } ?? false) { _, matches in
                undoToast?.undoesWithCommandZ = matches
            }
    }

    /// The sidebar with the other features' parts: the pull requests page, and each task row's pull
    /// request, branch state and context usage.
    /// Settings takes over the window while it's open. The split view's state lives
    /// here, so leaving Settings returns to where you were.
    @ViewBuilder
    private var content: some View {
        @Bindable var settings = settings
        if settings.isShown {
            SettingsScreen(
                pane: $settings.pane,
                additionalPanes: AppSettingsPanes.all(
                    plugins: model.plugins, terminals: terminals, keepAwake: keepAwake, projects: model.projects.all))
        } else {
            splitView
        }
    }

    private var splitView: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            sidebar
                .dsSidebarColumnTransparency()
                // The only sidebar toggle is ours, right after the window controls; as a
                // sidebar toolbar item it stays there when the sidebar is hidden, too. The system's
                // goes from both the column and the split view. On the column it must come before
                // the width, or SwiftUI drops the width.
                .toolbar(removing: .sidebarToggle)
                .onGeometryChange(for: CGFloat.self) {
                    $0.size.width
                } action: {
                    sidebarWidth.value = $0
                }
                .platformMinimumContentWidth(DS.Window.sidebarMinWidth)
                .navigationSplitViewColumnWidth(min: DS.Window.sidebarMinWidth, ideal: sidebarWidth.value, max: 380)
                .toolbar {
                    ToolbarItem {
                        SidebarCollapseButton(isExpanded: columnVisibility != .detailOnly) {
                            withAnimation {
                                columnVisibility = columnVisibility == .detailOnly ? .all : .detailOnly
                            }
                        }
                    }
                    .sharedBackgroundVisibility(.hidden)
                    ToolbarItem {
                        TranscriptSearchToolbarButton()
                    }
                    .sharedBackgroundVisibility(.hidden)
                    if releaseChannel.isNightly {
                        ToolbarItem {
                            NightlyMark()
                                .foregroundStyle(.dsTextTertiary)
                        }
                        .sharedBackgroundVisibility(.hidden)
                    }
                    // Pushes the toggle and search to the leading edge, next to the window controls, and
                    // back and forward to its trailing edge, by the content they navigate.
                    ToolbarSpacer(.flexible)
                    // The update button: right-aligned before back and forward, and still there when
                    // the sidebar is hidden. It shows only when an update needs the user.
                    if let updates, updates.showsToolbarButton {
                        ToolbarItem {
                            UpdateToolbarButton(controller: updates)
                        }
                        .sharedBackgroundVisibility(.hidden)
                    }
                    // They belong to the sidebar's header, so they go away with it (⌘[ and ⌘] still work).
                    if columnVisibility != .detailOnly {
                        ToolbarItem {
                            HistoryNavigationButtons(
                                canGoBack: model.canGoBack,
                                canGoForward: model.canGoForward,
                                onBack: model.goBack,
                                onForward: model.goForward
                            )
                        }
                        .sharedBackgroundVisibility(.hidden)
                    }
                }
        } detail: {
            // The background host's notices sit above the page, not over it: the page starts under
            // them, so a short transcript isn't hidden behind them, and a page's toolbar band
            // (`dsToolbarBand`) only reaches the notices' bottom edge.
            RootDetailColumn {
                if let durableHost {
                    HostNotices(host: durableHost, updates: updates)
                }
            } content: {
                detail
            }
            // Under every page, so the transcript and anything else without a background of its
            // own sits on the design system's background in the user's light tone, not the system's.
            .background(.dsBackground)
            .environment(\.inspectorRoom, inspectorRoom.room(sidebar: $columnVisibility))
            .environment(\.sessionTranscriptMemory, transcriptMemory)
        }
        .toolbar(removing: .sidebarToggle)
        .tracksWindowRoom(inspectorRoom.window)
        .onChange(of: columnVisibility) { _, visibility in
            inspectorRoom.sidebarChanged(to: visibility)
        }
    }

    private var sidebar: some View {
        SidebarView {
            PullRequestsNavItem(isSelected: showsPullRequests) { showsPullRequests = true }
            // Minimal by default: only when goals and workflows are on, or a run is there to see.
            if model.plugins.isEnabled(BuiltInPlugins.automation.manifest.id) || !automation.workflows.runs.isEmpty {
                WorkflowsNavItem(isSelected: automationPage == .workflows) { automationPage = .workflows }
            }
            if model.plugins.isEnabled(BuiltInPlugins.automations.manifest.id)
                || !automation.automations.automations.isEmpty
            {
                AutomationsNavItem(isSelected: automationPage == .automations) { automationPage = .automations }
            }
            if model.plugins.isEnabled(BuiltInPlugins.expeditions.manifest.id) || expeditions.hasExpeditions {
                ExpeditionsNavItem(isSelected: expeditions.isPageShown) { expeditions.show() }
            }
        } accessories: {
            EmptyView()
        } taskAccessory: { summary in
            AppTaskRowAccessory(summary: summary)
        }
        .environment(\.sidebarTaskInsights, AppSidebarTaskInsights.make(model: model, git: git, gitHub: gitHub))
    }

    /// Turns Automations on and opens it, from the Workflows page; nil once it's in the sidebar.
    private var automationsSetUp: (() -> Void)? {
        let id = BuiltInPlugins.automations.manifest.id
        guard !model.plugins.isEnabled(id), automation.automations.automations.isEmpty else { return nil }
        return {
            model.plugins.setEnabled(true, for: id)
            automationPage = .automations
        }
    }

    private var signInAgent: AgentRuntime? {
        model.signInPrompt.flatMap(model.runtime)
    }

    @ViewBuilder
    private var detail: some View {
        if showsPullRequests {
            PullRequestsView()
        } else if automationPage == .workflows {
            WorkflowsPage(path: $workflowPath, onSetUpAutomations: automationsSetUp) { session in
                TranscriptView(session: session) { _ in }
            }
        } else if expeditions.isPageShown {
            ExpeditionsPage { session in
                TranscriptView(session: session) { _ in }
            }
        } else if automationPage == .automations {
            AutomationsPage { run in
                workflowPath = [run]
                automationPage = .workflows
            }
        } else if let key = model.selection {
            if let task = model.startingTask(key) {
                StartingTaskView(task: task)
                    .id(key)
            } else if let session = model.session(key) {
                SessionView(session: session)
                    .id(key)
            } else {
                openingSession(key)
            }
        } else {
            HomeDetail()
        }
    }

    /// A selected session on its way in: its agent starting first if it was idle, or why it can't.
    @ViewBuilder
    private func openingSession(_ key: SessionKey) -> some View {
        // Nothing would load it (a notification for a task deleted since, say), so it would spin forever.
        if !model.catalog.contains(key) {
            EmptyStateView(
                "This Task Isn't Available Any More", systemImage: "questionmark.circle",
                message: "It was deleted, or its agent no longer lists it.",
                actionTitle: "Go Back"
            ) {
                goBack()
            }
        } else if let failure = model.openFailures[key] {
            SessionOpenFailureView(
                failure: failure, onRetry: { Task { await model.loadSession(key) } }, onGoBack: goBack)
        } else if let runtime = model.runtime(key.agent), runtime.status.canRetry {
            let isMissing = if case .notInstalled = runtime.status { true } else { false }
            EmptyStateView(
                "Couldn't Start \(runtime.agent.displayName)", systemImage: "exclamationmark.triangle",
                message: runtime.status.guidance,
                actionTitle: isMissing ? "Check Again" : "Restart \(runtime.agent.displayName)"
            ) {
                Task { await model.restart(key.agent) }
            }
        } else if let runtime = model.runtime(key.agent), runtime.status == .starting {
            LoadingStateView("Starting \(runtime.agent.displayName)…")
        } else {
            LoadingStateView("Opening the task…")
        }
    }

    /// Leaves a task that can't be shown for the last place in history, or home.
    private func goBack() {
        if model.canGoBack { model.goBack() } else { model.selection = nil }
    }
}

/// A plain reference rather than state, so tracking the width while the user drags doesn't redraw
/// the window.
private final class RootSidebarWidth {
    var value = DS.Size.sidebarWidth
}

extension FocusedValues {
    /// The main window's sidebar visibility, for the View menu's sidebar command.
    @Entry var sidebarVisibility: Binding<NavigationSplitViewVisibility>?
}

extension URL {
    /// The path with the home directory shown as `~`.
    var abbreviatedPath: String {
        (path(percentEncoded: false) as NSString).abbreviatingWithTildeInPath
    }
}
