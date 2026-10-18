import Foundation
import NativeHostProtocol
import NativeLink
import Observation

/// Every host this phone is paired with, each with its own connection, plus the add-host flow a
/// pairing link opens. Hosts are separate: unpairing one never touches another.
@Observable
final class CompanionStore {
    private(set) var hosts: [HostConnection] = []
    /// Hosts Bonjour sees on this network, for pairing by code and for finding paired ones.
    private(set) var discovered: [DiscoveredHost] = []
    /// A pairing link that opened the app (scanned with the Camera, or pasted); the add flow shows it.
    var pendingInvite: PairingInvite?
    var isAddingHost = false
    var problem: String?

    @ObservationIgnored private let store: any PairedHostStore
    @ObservationIgnored private let browser = LinkBrowser()
    @ObservationIgnored private var browsing: Task<Void, Never>?

    init(store: any PairedHostStore) {
        self.store = store
        let browser = browser
        do {
            hosts = try store.hosts().map { HostConnection(host: $0, discovered: { browser.current }) }
        } catch {
            problem = "Couldn't read paired hosts: \(error.localizedDescription)"
        }
        for host in hosts { configure(host) }
        browsing = Task { [weak self] in
            for await found in browser.results {
                self?.discovered = found
            }
        }
    }

    func host(_ id: HostID) -> HostConnection? {
        hosts.first { $0.id == id }
    }

    func startAll() {
        for host in hosts { host.start() }
    }

    /// Keeps a new pairing. Pairing the same host instance again replaces its old pairing.
    func add(_ pairedHost: PairedHost) {
        do {
            try store.save(pairedHost)
        } catch {
            problem = "Paired, but couldn't save it: \(error.localizedDescription)"
        }
        if let existing = host(pairedHost.hostID) {
            existing.stop()
            hosts.removeAll { $0.id == pairedHost.hostID }
        }
        let browser = browser
        let connection = HostConnection(host: pairedHost, discovered: { browser.current })
        configure(connection)
        hosts.append(connection)
        connection.start()
    }

    func unpair(_ connection: HostConnection) {
        connection.stop()
        try? store.remove(connection.id)
        HostPreferences.remove(for: connection.id)
        hosts.removeAll { $0.id == connection.id }
    }

    /// Opens the add flow for a `nativecompanion://pair#…` link.
    func open(_ url: URL) {
        do {
            pendingInvite = try PairingInvite(url: url.absoluteString)
            isAddingHost = true
        } catch {
            problem = error.localizedDescription
        }
    }

    private func configure(_ connection: HostConnection) {
        connection.onUpdateAvailable = { host, release in
            guard host.preferences.notifiesAboutUpdates else { return }
            CompanionNotifications.postUpdateAvailable(hostName: host.name, hostID: host.id, version: release.version)
        }
    }
}
