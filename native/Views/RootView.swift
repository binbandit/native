import ACP
import SwiftUI
import UniformTypeIdentifiers

struct RootView: View {
    @Environment(AppModel.self) private var model
    @State private var columnVisibility = NavigationSplitViewVisibility.all

    var body: some View {
        @Bindable var model = model
        NavigationSplitView(columnVisibility: $columnVisibility) {
            SidebarView()
                .navigationSplitViewColumnWidth(min: 220, ideal: DS.Size.sidebarWidth, max: 380)
                // The only sidebar toggle is ours (the split view's own is removed below), right after
                // the window controls as in Factory. As a sidebar toolbar item it stays there when the
                // sidebar is hidden, too.
                .toolbar {
                    ToolbarItem {
                        SidebarCollapseButton(isExpanded: columnVisibility != .detailOnly) {
                            withAnimation {
                                columnVisibility = columnVisibility == .detailOnly ? .all : .detailOnly
                            }
                        }
                    }
                    .sharedBackgroundVisibility(.hidden)
                    // Pushes the toggle to the sidebar's leading edge, next to the window controls, and
                    // back and forward to its trailing edge, where Conductor has them.
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
        // Here rather than on the sidebar column, where it makes SwiftUI drop the column's width.
        .toolbar(removing: .sidebarToggle)
        .focusedSceneValue(\.sidebarVisibility, $columnVisibility)
        .task(id: model.selection) {
            if let key = model.selection {
                await model.loadSession(key)
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

    private var signInAgent: AgentRuntime? {
        model.signInPrompt.flatMap(model.runtime)
    }

    @ViewBuilder
    private var detail: some View {
        if let key = model.selection {
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
}

extension URL {
    /// The path with the home directory shown as `~`.
    var abbreviatedPath: String {
        (path(percentEncoded: false) as NSString).abbreviatingWithTildeInPath
    }
}
