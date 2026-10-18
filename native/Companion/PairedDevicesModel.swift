import Foundation
import NativeLink
import Observation

/// Settings › Paired Devices and the Pair iPhone sheet, over the host gateway's control socket
/// (`docs/companion.md`). Every action is a method here, so nothing in the views talks to the
/// gateway directly.
@Observable
final class PairedDevicesModel {
    private(set) var status: LinkStatus?
    /// Why the gateway can't be reached right now (the background host is off or starting).
    private(set) var unavailableReason: String?
    var errorMessage: String?
    var undo: UndoToastItem?
    /// Whether the Pair iPhone sheet is showing; while it is, an expired code is replaced on its own.
    private(set) var isPairing = false

    @ObservationIgnored private var client: LinkControlClient?
    @ObservationIgnored private var listening: Task<Void, Never>?
    @ObservationIgnored private var refreshing: Task<Void, Never>?

    var activeDevices: [LinkDeviceStatus] {
        status?.activeDevices.sorted { $0.device.pairedAt > $1.device.pairedAt } ?? []
    }

    func start(hostDirectory: URL) {
        guard client == nil else { return }
        let client = LinkControlClient(hostDirectory: hostDirectory)
        self.client = client
        listening = Task { [weak self] in
            await client.start()
            for await event in client.events {
                self?.apply(event)
            }
        }
    }

    func stop() {
        listening?.cancel()
        refreshing?.cancel()
        if let client {
            Task { await client.stop() }
        }
        client = nil
    }

    private func apply(_ event: LinkControlClient.Event) {
        switch event {
        case .status(let status):
            self.status = status
            unavailableReason = nil
            scheduleRefresh(for: status.pairing)
        case .unavailable(let reason):
            unavailableReason = reason
        }
    }

    // MARK: - Pairing

    func beginPairing() {
        isPairing = true
        perform { try await $0.openPairingWindow() }
    }

    func endPairing() {
        isPairing = false
        refreshing?.cancel()
        perform { try await $0.closePairingWindow() }
    }

    func newCode() {
        perform { try await $0.openPairingWindow() }
    }

    func decide(accept: Bool, grants: LinkGrants) {
        perform { try await $0.decidePairing(accept: accept, grants: grants) }
    }

    /// Codes last five minutes; an open sheet gets a fresh one the moment its code runs out.
    private func scheduleRefresh(for pairing: LinkPairingStatus?) {
        refreshing?.cancel()
        guard isPairing, let pairing, pairing.phase == .open else { return }
        let delay = max(pairing.expiresAt.timeIntervalSinceNow, 0)
        refreshing = Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled else { return }
            self?.newCode()
        }
    }

    // MARK: - Devices

    func revoke(_ device: LinkDevice) {
        perform { try await $0.revoke(device.id) }
        undo = UndoToastItem("Removed “\(device.name)”. It can't connect until you undo or pair it again.") {
            [weak self] in
            self?.perform { try await $0.restore(device.id) }
        }
    }

    func rename(_ device: LinkDevice, to name: String) {
        perform { try await $0.rename(device.id, to: name) }
    }

    func setGrants(_ grants: LinkGrants, for device: LinkDevice) {
        perform { try await $0.setGrants(device.id, to: grants) }
    }

    func setEnabled(_ isEnabled: Bool) {
        perform { try await $0.setEnabled(isEnabled) }
    }

    private func perform(_ action: @escaping @Sendable (LinkControlClient) async throws -> LinkStatus) {
        guard let client else { return }
        Task { [weak self] in
            do {
                _ = try await action(client)
                self?.errorMessage = nil
            } catch {
                self?.errorMessage = error.localizedDescription
            }
        }
    }
}
