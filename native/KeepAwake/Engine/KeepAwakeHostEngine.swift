import Foundation
import NativeHostClient
import NativeHostProtocol

/// Keeps the Mac awake through its background host (docs/durability.md, "Sleep"): the host holds
/// the assertions while its sessions work, after Native quits too, and counts those sessions
/// itself, so the app's own activity doesn't matter here. This sends the policy and reports what
/// the host says it's doing.
final class KeepAwakeHostEngine: KeepAwakeEngine {
    var onChange: ((KeepAwakeStatus) -> Void)?

    private let client: NativeHostClient
    private var status = KeepAwakeStatus.off
    /// The policy to keep the host on; sent again after every reconnect, since the user may have
    /// changed it while the host was away.
    private var policy: KeepAwakePolicy?
    private var sending: Task<Void, Never>?

    init(client: NativeHostClient) {
        self.client = client
        Task { [weak self] in
            await client.addStatusHandler { [weak self] status in
                await self?.received(status.keepAwake)
            }
            await client.addEventHandler { [weak self] event in
                // Handlers must not wait on the client's requests; `send` sends on its own task.
                if case .connection(.connected) = event {
                    await self?.send()
                }
            }
        }
    }

    func apply(_ policy: KeepAwakePolicy, activity: KeepAwakeActivity) -> KeepAwakeStatus {
        if policy != self.policy {
            self.policy = policy
            send()
        }
        return status
    }

    /// The host keeps the Mac awake by the policy whatever the app does, so there's nothing to let
    /// go of here.
    func stop() {}

    private func send() {
        guard let policy else { return }
        sending?.cancel()
        sending = Task { [client] in
            guard let state = try? await client.setKeepAwake(policy), !Task.isCancelled else { return }
            received(state)
        }
    }

    private func received(_ state: HostKeepAwakeState) {
        guard state.status != status else { return }
        status = state.status
        onChange?(status)
    }
}
