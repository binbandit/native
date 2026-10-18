import NativeLink
import SwiftUI

/// Native for iPhone: a window onto the hosts this phone is paired with, and a remote for them.
/// Nothing runs here; every host keeps its agents (`docs/companion.md`).
@main
struct NativeCompanionApp: App {
    @State private var store: CompanionStore
    @AppStorage(CompanionAppearance.key) private var appearance = CompanionAppearance.system
    @AppStorage(CompanionAppIcon.key) private var iconTheme = CompanionAppIcon.original.rawValue

    init() {
        let pairings = KeychainPairedHostStore(service: CompanionDevice.keychainService)
        // UI tests start from a phone that has never paired.
        if ProcessInfo.processInfo.arguments.contains("-companionForgetPairings") {
            for host in (try? pairings.hosts()) ?? [] { try? pairings.remove(host.hostID) }
        }
        _store = State(initialValue: CompanionStore(store: pairings))
    }

    var body: some Scene {
        WindowGroup {
            CompanionRootView()
                .environment(store)
                .preferredColorScheme(appearance.colorScheme)
                .dsAccentPalette(themeID: iconTheme)
                .onOpenURL { store.open($0) }
                .task { store.startAll() }
        }
    }
}
