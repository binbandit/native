import Foundation
import NativePolicy

/// A revocable response. Consumers publish/cache through `publish`, not by saving raw transport output.
public struct NetworkReceipt: Sendable {
    public let response: NetworkHTTPResponse
    fileprivate let revision: UInt64
    fileprivate let clientID: UUID
    fileprivate let service: NativePolicy.NetworkService
    fileprivate let destinations: [URL]
}

/// Serializes admission and publication with policy revision changes. Cancellation is cooperative;
/// even a transport that ignores cancellation cannot publish a stale response.
public final class NetworkClient: @unchecked Sendable {
    private let lock = NSRecursiveLock()
    private let provider: @Sendable () -> NativePolicy?
    private let transport: any NetworkHTTPTransport
    private let id = UUID()
    private var snapshot: NativePolicy.Network?
    private var revision: UInt64 = 0
    private var operations: [UUID: Task<NetworkHTTPResponse, Error>] = [:]
    private var watch: Task<Void, Never>?

    public init(
        policy: @escaping @Sendable () -> NativePolicy?,
        updates: AsyncStream<NativePolicy>? = nil,
        transport: any NetworkHTTPTransport = URLSessionNetworkTransport()
    ) {
        provider = policy
        self.transport = transport
        snapshot = policy()?.network
        if let updates {
            watch = Task { [weak self] in
                for await policy in updates {
                    guard !Task.isCancelled else { return }
                    self?.acceptUpdate(policy.network)
                }
            }
        }
    }

    deinit {
        watch?.cancel()
        for operation in operations.values { operation.cancel() }
    }

    /// Call synchronously when an injected policy source changes. Production also observes defaults.
    public func policyDidChange() {
        lock.withLock { synchronize() }
    }

    public var policyRevision: UInt64 {
        lock.withLock {
            synchronize()
            return revision
        }
    }

    private func acceptUpdate(_ network: NativePolicy.Network) {
        lock.withLock { replaceSnapshot(network) }
    }

    private func synchronize() { replaceSnapshot(provider()?.network) }

    private func replaceSnapshot(_ current: NativePolicy.Network?) {
        guard current != snapshot else { return }
        snapshot = current
        revision &+= 1
        // Cancelling all old revisions also covers endpoint changes and remove/re-add races.
        operations.values.forEach { $0.cancel() }
    }

    public func endpoint(for service: NativePolicy.NetworkService, default defaultURL: URL?) -> URL? {
        lock.withLock {
            synchronize()
            return snapshot?.services[service]?.endpoint ?? defaultURL
        }
    }

    public func checkService(_ service: NativePolicy.NetworkService) throws {
        try lock.withLock {
            synchronize()
            try NetworkAdmission.checkService(service: service, policy: snapshot)
        }
    }

    public func check(service: NativePolicy.NetworkService, url: URL) throws {
        try lock.withLock {
            synchronize()
            try NetworkAdmission.check(service: service, destination: .url(url), policy: snapshot)
        }
    }

    public func get(service: NativePolicy.NetworkService, url: URL) async throws -> NetworkReceipt {
        let startRevision = try lock.withLock {
            synchronize()
            try NetworkAdmission.check(service: service, destination: .url(url), policy: snapshot)
            return revision
        }
        var current = url
        var destinations: [URL] = []
        for hop in 0...5 {
            if Task.isCancelled { throw NetworkFailure(service: service, reason: .cancelled) }
            let operationID = UUID()
            let requestedURL = current
            let operation = try lock.withLock {
                synchronize()
                guard revision == startRevision else { throw NetworkFailure(service: service, reason: .revoked) }
                try NetworkAdmission.check(service: service, destination: .url(current), policy: snapshot)
                guard let origin = NetworkOrigin(url: current), ["https", "http"].contains(origin.scheme) else {
                    throw NetworkFailure(service: service, reason: .unsupportedScheme)
                }
                let task = Task { [transport] in
                    try Task.checkCancellation()
                    return try await transport.send(requestedURL)
                }
                operations[operationID] = task
                return task
            }
            let response: NetworkHTTPResponse
            do {
                response = try await withTaskCancellationHandler {
                    try await operation.value
                } onCancel: {
                    operation.cancel()
                }
            } catch {
                let reason: NetworkFailure.Reason = lock.withLock {
                    operations.removeValue(forKey: operationID)
                    synchronize()
                    if Task.isCancelled { return .cancelled }
                    return revision == startRevision ? .transportFailed : .revoked
                }
                throw NetworkFailure(service: service, reason: reason)
            }
            try lock.withLock {
                operations.removeValue(forKey: operationID)
                synchronize()
                guard revision == startRevision else { throw NetworkFailure(service: service, reason: .revoked) }
                guard !Task.isCancelled else { throw NetworkFailure(service: service, reason: .cancelled) }
                guard let final = NetworkOrigin(url: response.url), final == NetworkOrigin(url: current) else {
                    throw NetworkFailure(service: service, reason: .finalOriginMismatch)
                }
                try NetworkAdmission.check(service: service, destination: .url(response.url), policy: snapshot)
            }
            destinations.append(current)
            guard [301, 302, 303, 307, 308].contains(response.status) else {
                return NetworkReceipt(
                    response: response, revision: startRevision, clientID: id, service: service,
                    destinations: destinations)
            }
            guard NetworkInventory.declaration(service).redirects == .approvedOrigins else {
                throw NetworkFailure(service: service, reason: .redirectDenied)
            }
            guard hop < 5 else { throw NetworkFailure(service: service, reason: .tooManyRedirects) }
            guard let location = response.location, let next = URL(string: location, relativeTo: current)?.absoluteURL,
                let origin = NetworkOrigin(url: next)
            else { throw NetworkFailure(service: service, reason: .invalidDestination) }
            try lock.withLock {
                synchronize()
                guard revision == startRevision else { throw NetworkFailure(service: service, reason: .revoked) }
                // A document URL grants one destination, never its implicit CDN/redirect chain.
                guard
                    origin == NetworkOrigin(url: current)
                        || snapshot?.services[service]?.origins.contains(origin) == true
                else { throw NetworkFailure(service: service, reason: .redirectDenied) }
                try NetworkAdmission.check(service: service, destination: .url(next), policy: snapshot)
            }
            current = next
        }
        throw NetworkFailure(service: service, reason: .tooManyRedirects)
    }

    /// The synchronous closure is the publication point. Do not suspend or invoke policy writers in it.
    public func publish<T>(_ receipt: NetworkReceipt, _ body: () throws -> T) throws -> T {
        try lock.withLock {
            synchronize()
            guard receipt.clientID == id, receipt.revision == revision else {
                throw NetworkFailure(service: receipt.service, reason: .revoked)
            }
            guard !Task.isCancelled else { throw NetworkFailure(service: receipt.service, reason: .cancelled) }
            for destination in receipt.destinations {
                try NetworkAdmission.check(service: receipt.service, destination: .url(destination), policy: snapshot)
            }
            return try body()
        }
    }
}
