#if DEBUG
import NativeHostProtocol
import SwiftUI

struct CompanionLayoutPreview: View {
    @State private var store: CompanionStore
    @State private var navigation: CompanionNavigation
    private let icons: AppIconController

    init(selectedTask: Bool = true) {
        let host = CompanionPreviewFixtures.host()
        let store = CompanionStore(previewHosts: [host])
        let navigation = CompanionNavigation()
        if selectedTask, let session = host.sessions.first {
            let route = TaskRoute(hostID: host.id, sessionID: session.id)
            navigation.selection = .task(route)
            navigation.state(for: route).draft = "Keep this draft while I unfold."
        }
        _store = State(initialValue: store)
        _navigation = State(initialValue: navigation)
        icons = AppIconController(
            store: store, celebrations: CompanionCelebrations(defaults: CompanionPreviewDefaults()),
            defaults: CompanionPreviewDefaults())
    }

    var body: some View {
        CompanionRootView(navigation: navigation)
            .environment(store)
            .environment(icons)
    }
}
#endif
