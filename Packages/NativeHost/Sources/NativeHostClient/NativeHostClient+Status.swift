import Foundation
import NativeHostProtocol
import Synchronization

// How the host's machine is doing, keeping it awake, and the doctor (docs/droids.md).
extension NativeHostClient {
    /// The machine's system, model, boot time and load, and its keep-awake state.
    public func hostStatus() async throws -> HostStatus {
        try await call(HostProtocol.Method.hostStatus, EmptyMessage())
    }

    /// Calls `handler` with the host's status from now on: about every 30 seconds while connected,
    /// and at once when keeping awake changes. In order with the client's events; like an event
    /// handler, it must never wait on a request to this client.
    public func addStatusHandler(_ handler: @escaping @Sendable (HostStatus) async -> Void) {
        route(HostProtocol.Method.hostStatusChanged, make: HostStatusRoute.init).add(handler)
    }

    /// Sets the policy the host keeps its machine awake by: the app's Keep Mac Awake setting.
    /// Local clients, and paired devices that may manage the host.
    public func setKeepAwake(_ policy: KeepAwakePolicy) async throws -> HostKeepAwakeState {
        try await call(HostProtocol.Method.setKeepAwake, SetKeepAwakeParams(policy: policy))
    }

    /// The doctor's read-only checks of the host's machine. Takes a few seconds: it asks each CLI
    /// for its version.
    public func doctor() async throws -> HostDoctorReport {
        try await call(HostProtocol.Method.doctor, EmptyMessage())
    }
}

/// Hands each `_native/host/status/changed` to the handlers that asked for status.
final class HostStatusRoute: HostNotificationRoute {
    private let handlers = Mutex<[@Sendable (HostStatus) async -> Void]>([])

    func add(_ handler: @escaping @Sendable (HostStatus) async -> Void) {
        handlers.withLock { $0.append(handler) }
    }

    func receive(_ message: JSONRPCPeer.Message) async {
        guard let status = try? message.params(as: HostStatusChangedNotification.self).status else { return }
        for handler in handlers.withLock({ $0 }) {
            await handler(status)
        }
    }
}
