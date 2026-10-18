import SwiftUI

/// First run until a host is paired, then the home screen. A pairing link opens the add flow from
/// anywhere.
struct CompanionRootView: View {
    @Environment(CompanionStore.self) private var store

    var body: some View {
        @Bindable var store = store
        Group {
            if store.hosts.isEmpty {
                WelcomeView { store.isAddingHost = true }
            } else {
                NavigationStack {
                    HomeView()
                }
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
}
