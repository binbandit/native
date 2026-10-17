import ACP
import NativeAutomation
import SwiftUI
import UniformTypeIdentifiers

struct RootView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.releaseChannel) private var releaseChannel
    @State private var columnVisibility = NavigationSplitViewVisibility.all
    /// The sidebar's width as the user left it. Settings replaces the split view, and a new one opens
    /// at its ideal width, so this is the ideal.
    @State private var sidebarWidth = RootSidebarWidth()
    @State private var undoToast: UndoToastItem?
    @State private var showsPullRequests = false
    @Environment(AutomationCenter.self) private var automation
    /// Workflows or Automations, when one of them has the detail column.
    @State private var automationPage: AutomationPage?
    /// The run open on the Workflows page, if any.
    @State private var workflowPath: [WorkflowRun.ID] = []
    @Environment(ExpeditionCenter.self) private var expeditions
    @Environment(SettingsPresentation.self) private var settings
    @Environment(TerminalStore.self) private var terminals

    var body: some View {
        @Bindable var model = model
        @Bindable var automation = automation
        content
            .focusedSceneValue(\.sidebarVisibility, $columnVisibility)
            .undoToast($undoToast)
            .onChange(of: model.lastUndoable?.id) {
                undoToast = model.lastUndoable.map { action in UndoToastItem(action.message, undo: action.undo) }
            }
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
            .confirmationDialog("New Session With", isPresented: $model.isChoosingAgent) {
                ForEach(model.agents, id: \.agent.id) { runtime in
                    Button(runtime.agent.displayName) {
                        Task { await model.newSession(with: runtime.agent.id) }
                    }
                    .disabled(!model.canCreateSession(with: runtime.agent.id))
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Choose the agent for the new session.")
            }
            .fileImporter(isPresented: $model.isAddingProject, allowedContentTypes: [.folder]) { result in
                if case .success(let url) = result {
                    Task { await model.addProject(url) }
                }
            }
            .alert(
                "Something Went Wrong",
                isPresented: Binding(get: { model.errorMessage != nil }, set: { if !$0 { model.errorMessage = nil } }),
                presenting: model.errorMessage
            ) { _ in
                Button("OK") {}
            } message: { message in
                Text(message)
            }
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
                Text("\(runtime.agent.displayName) needs you to sign in before it can start a session.")
            }
    }

    /// The sidebar with the other features' parts: the pull requests page, and each task row's pull
    /// request, branch state and context usage.
    /// Settings takes over the window while it's open, as in the reference app. The split view's state lives
    /// here, so leaving Settings returns to where you were.
    @ViewBuilder
    private var content: some View {
        @Bindable var settings = settings
        if settings.isShown {
            SettingsScreen(
                pane: $settings.pane,
                additionalPanes: AppSettingsPanes.all(plugins: model.plugins, terminals: terminals))
        } else {
            splitView
        }
    }

    private var splitView: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            sidebar
                // The only sidebar toggle is ours, right after the window controls as in the reference app; as a
                // sidebar toolbar item it stays there when the sidebar is hidden, too. The system's
                // goes from both the column and the split view. On the column it must come before
                // the width, or SwiftUI drops the width.
                .toolbar(removing: .sidebarToggle)
                .onGeometryChange(for: CGFloat.self) {
                    $0.size.width
                } action: {
                    sidebarWidth.value = $0
                }
                .navigationSplitViewColumnWidth(min: 220, ideal: sidebarWidth.value, max: 380)
                .toolbar {
                    ToolbarItem {
                        SidebarCollapseButton(isExpanded: columnVisibility != .detailOnly) {
                            withAnimation {
                                columnVisibility = columnVisibility == .detailOnly ? .all : .detailOnly
                            }
                        }
                    }
                    .sharedBackgroundVisibility(.hidden)
                    if releaseChannel.isNightly {
                        ToolbarItem {
                            NightlyMark()
                                .foregroundStyle(.dsTextTertiary)
                        }
                        .sharedBackgroundVisibility(.hidden)
                    }
                    // Pushes the toggle to the sidebar's leading edge, next to the window controls, and
                    // back and forward to its trailing edge, where the reference app has them.
                    ToolbarSpacer(.flexible)
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
            detail
        }
        .toolbar(removing: .sidebarToggle)
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
            if let session = model.session(key) {
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
        if let runtime = model.runtime(key.agent), runtime.status.canRetry {
            let isMissing = if case .notInstalled = runtime.status { true } else { false }
            EmptyStateView(
                "Couldn't Start \(runtime.agent.displayName)", systemImage: "exclamationmark.triangle",
                message: runtime.status.guidance,
                actionTitle: isMissing ? "Check Again" : "Restart \(runtime.agent.displayName)"
            ) {
                Task { await model.restart(key.agent) }
            }
        } else if let runtime = model.runtime(key.agent), runtime.status == .starting {
            ProgressView("Starting \(runtime.agent.displayName)…")
                .controlSize(.small)
                .font(.dsBody)
                .foregroundStyle(.dsTextSecondary)
        } else {
            ProgressView()
                .controlSize(.small)
        }
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
