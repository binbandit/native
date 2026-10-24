import NativeLink
import SwiftUI

/// Native for iPhone: a window onto the hosts this phone is paired with, and a remote for them.
/// Nothing runs here; every host keeps its agents (`docs/companion.md`).
@main
struct NativeCompanionApp: App {
    @State private var store: CompanionStore
    @State private var icons: AppIconController
    @AppStorage(CompanionAppearance.key) private var appearance = CompanionAppearance.system
    @Environment(\.scenePhase) private var scenePhase

    init() {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-companionLayoutPreview") {
            let store = CompanionStore(previewHosts: [])
            _store = State(initialValue: store)
            _icons = State(
                initialValue: AppIconController(
                    store: store, celebrations: CompanionCelebrations(defaults: CompanionPreviewDefaults()),
                    defaults: CompanionPreviewDefaults()))
            return
        }
        #endif
        let pairings = KeychainPairedHostStore(service: CompanionDevice.keychainService)
        // UI tests start from a phone that has never paired.
        if ProcessInfo.processInfo.arguments.contains("-companionForgetPairings") {
            for host in (try? pairings.hosts()) ?? [] { try? pairings.remove(host.hostID) }
        }
        let store = CompanionStore(store: pairings)
        _store = State(initialValue: store)
        _icons = State(initialValue: AppIconController(store: store, celebrations: CompanionCelebrations()))
    }

    var body: some Scene {
        WindowGroup {
            root
                .environment(store)
                .environment(icons)
                .preferredColorScheme(appearance.colorScheme)
                .dsAccentPalette(themeID: icons.theme.rawValue)
                .onOpenURL { store.open($0) }
                .task { store.startAll() }
                .onChange(of: scenePhase, initial: true) { _, phase in
                    if phase == .active { icons.applyDue() }
                }
                // Switching hosts is the person's own change; a celebration's dates wait for the
                // next activation rather than interrupting with the system's alert.
                .onChange(of: store.activeHostID) { icons.applyNow() }
        }
    }

    @ViewBuilder
    private var root: some View {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-companionLayoutPreview") {
            CompanionLayoutPreview(
                selectedTask: !ProcessInfo.processInfo.arguments.contains("-companionPreviewHome"))
        } else {
            CompanionRootView()
        }
        #else
        CompanionRootView()
        #endif
    }
}
