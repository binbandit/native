import SwiftUI

/// First run until a host is paired, then the home screen. A pairing link opens the add flow from
/// anywhere.
struct CompanionRootView: View {
    @Environment(CompanionStore.self) private var store
    @State private var navigation = CompanionNavigation()

    init(navigation: CompanionNavigation = CompanionNavigation()) {
        _navigation = State(initialValue: navigation)
    }

    var body: some View {
        @Bindable var store = store
        @Bindable var navigation = navigation
        Group {
            if store.hosts.isEmpty {
                WelcomeView { store.isAddingHost = true }
            } else {
                NavigationSplitView {
                    HomeView(selection: $navigation.selection)
                } detail: {
                    NavigationStack {
                        destination
                            .navigationDestination(for: TaskRoute.self) { route in
                                task(route)
                            }
                    }
                    .id(navigation.selection)
                }
                .navigationSplitViewStyle(.balanced)
            }
        }
        .background(.dsBackground)
        .sheet(isPresented: $store.isAddingHost, onDismiss: { store.pendingInvite = nil }) {
            AddHostView()
        }
        .alert(
            "Something went wrong",
            isPresented: Binding(get: { store.problem != nil }, set: { if !$0 { store.problem = nil } })
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(store.problem ?? "")
        }
    }

    @ViewBuilder
    private var destination: some View {
        switch navigation.selection {
        case .task(let route):
            task(route)
        case .host(let id):
            if let host = store.host(id) { HostDetailView(host: host) }
        case .allTasks(let id):
            if let host = store.host(id) { HostTasksView(host: host) }
        case nil:
            EmptyStateView(
                "Choose a task", systemImage: "bubble.left.and.bubble.right",
                message: "Select a task to read its conversation, send a message or answer a request."
            )
            .background(.dsBackground)
        }
    }

    @ViewBuilder
    private func task(_ route: TaskRoute) -> some View {
        if let host = store.host(route.hostID) {
            TaskView(host: host, sessionID: route.sessionID, state: navigation.state(for: route))
                .id(route)
        }
    }
}

#if DEBUG
#Preview("Companion - Compact") {
    DSPreviewPair {
        CompanionLayoutPreview()
            .environment(\.horizontalSizeClass, .compact)
            .frame(width: 390, height: 760)
    }
}

#Preview("Companion - Regular") {
    DSPreviewPair {
        CompanionLayoutPreview()
            .environment(\.horizontalSizeClass, .regular)
            .frame(width: 900, height: 760)
    }
}
#endif
