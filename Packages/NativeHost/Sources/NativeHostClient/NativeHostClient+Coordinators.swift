import Foundation
import NativeHostProtocol
import Synchronization

public extension NativeHostClient {
    func newCoordinator(_ params: NewCoordinatorParams) async throws -> HostSessionSummary {
        var params = params
        guard params.task.attach else { return try await call(HostProtocol.Method.newCoordinator, params) }
        let session = params.task.sessionID ?? HostSessionID()
        params.task.sessionID = session
        return try await following(session) { try await $0.call(HostProtocol.Method.newCoordinator, params) }
    }

    func coordinators() async throws -> [HostCoordinator] {
        try await call(HostProtocol.Method.listCoordinators, EmptyMessage())
    }

    func setCoordinator(_ record: HostCoordinator) async throws {
        let _: EmptyMessage = try await call(HostProtocol.Method.setCoordinator, record)
    }

    func addCoordinatorHandler(_ handler: @escaping @Sendable ([HostCoordinator]) async -> Void) {
        route(HostProtocol.Method.coordinatorsChanged, make: CoordinatorChangesRoute.init).add(handler)
    }
}

final class CoordinatorChangesRoute: HostNotificationRoute {
    private let handlers = Mutex<[@Sendable ([HostCoordinator]) async -> Void]>([])

    func add(_ handler: @escaping @Sendable ([HostCoordinator]) async -> Void) {
        handlers.withLock { $0.append(handler) }
    }

    func receive(_ message: JSONRPCPeer.Message) async {
        guard let records = try? message.params(as: [HostCoordinator].self) else { return }
        for handler in handlers.withLock({ $0 }) { await handler(records) }
    }
}
