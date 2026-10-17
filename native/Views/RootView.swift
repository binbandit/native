import ACP
import NativeAutomation
import SwiftUI
import UniformTypeIdentifiers

struct RootView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.releaseChannel) private var releaseChannel
    @State private var columnVisibility = NavigationSplitViewVisibility.all
    @State private var undoToast: UndoToastItem?
    @Environment(\.undoManager) private var undoManager
    @State private var showsPullRequests = false
    @Environment(AutomationCenter.self) private var automation
    /// Workflows or Automations, when one of them has the detail column.
    @State private var automationPage: AutomationPage?
    /// The run open on the Workflows page, if any.
    @State private var workflowPath: [WorkflowRun.ID] = []

    var body: some View {
        @Bindable var model = model
        @Bindable var automation = automation
        NavigationSplitView(columnVisibility: $columnVisibility) {
            sidebar
                // The only sidebar toggle is ours, right after the window controls as in the reference app; as a
                // sidebar toolbar item it stays there when the sidebar is hidden, too. The system's
                // goes from both the column and the split view. On the column it must come before
                // the width, or SwiftUI drops the width.
                .toolbar(removing: .sidebarToggle)
                .navigationSplitViewColumnWidth(min: 220, ideal: DS.Size.sidebarWidth, max: 380)
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
        .focusedSceneValue(\.sidebarVisibility, $columnVisibility)
        .focusedSceneValue(\.windowUndoManager, undoManager)
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
            }
        }
        .onChange(of: automationPage) { _, page in
            if page != nil {
                model.selection = nil
                showsPullRequests = false
            }
        }
        .onChange(of: model.selection) { _, key in
            if key != nil {
                showsPullRequests = false
                automationPage = nil
            }
        }
        .sheet(isPresented: $automation.isWorkflowPickerRequested) {
            WorkflowPickerSheet(cwd: model.currentProject?.url, onAddProject: { model.isAddingProject = true }) { run in
                automationPage = .workflows
                workflowPath = [run]
            }
        }
        .task(id: model.selection) {
            if let key = model.selection {
                await model.loadSession(key)
            }
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
                        if await model.signIn(to: runtime.agent.id, with: method) {
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
    private var sidebar: some View {
        SidebarView {
            PullRequestsNavItem(isSelected: showsPullRequests) { showsPullRequests = true }
            // Minimal by default: only when goals and workflows are on, or a run is there to see.
            if model.plugins.isEnabled(BuiltInPlugins.automation.manifest.id) || !automation.workflows.runs.isEmpty {
                WorkflowsNavItem(isSelected: automationPage == .workflows) { automationPage = .workflows }
            }
            if model.plugins.isEnabled(BuiltInPlugins.automations.manifest.id) || !automation.automations.automations.isEmpty {
                AutomationsNavItem(isSelected: automationPage == .automations) { automationPage = .automations }
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
                ProgressView()
            }
        } else {
            HomeDetail()
        }
    }
}

extension FocusedValues {
    /// The main window's sidebar visibility, for the View menu's sidebar command.
    @Entry var sidebarVisibility: Binding<NavigationSplitViewVisibility>?
    /// The main window's undo manager, so menu commands can make their actions undoable.
    @Entry var windowUndoManager: UndoManager?
}

extension URL {
    /// The path with the home directory shown as `~`.
    var abbreviatedPath: String {
        (path(percentEncoded: false) as NSString).abbreviatingWithTildeInPath
    }
}
