import Foundation
import NativePolicy
import Testing

@testable import NativeNetwork

@Suite(.timeLimit(.minutes(1))) struct NetworkAdmissionTests {
    private func url(_ text: String = "https://icons.example/a.svg") throws -> URL { try #require(URL(string: text)) }

    @Test func inventoryIsCompleteAndIndividuallyDeniable() throws {
        #expect(Set(NetworkInventory.runtime.map(\.service)) == Set(NativePolicy.NetworkService.allCases))
        #expect(
            NetworkInventory.runtime.filter { $0.integration == .mediated }.map(\.service) == [.iconIndex, .iconAssets])
        for entry in NetworkInventory.runtime {
            var policy = NativePolicy.Network()
            policy.services[entry.service] = .init(enabled: false)
            #expect(throws: NetworkFailure(service: entry.service, reason: .disabled)) {
                try NetworkAdmission.check(service: entry.service, destination: .url(url()), policy: policy)
            }
            #expect(!entry.owner.isEmpty && !entry.trigger.isEmpty && !entry.payload.isEmpty && !entry.offline.isEmpty)
        }
    }

    @Test func deniedBeforeResolverOrTransport() async throws {
        var denied = NativePolicy()
        denied.network.services[.iconAssets] = .init(enabled: false)
        let policies: [NativePolicy?] = [
            nil, denied,
            PolicyLoader.load(
                from: StaticPolicySource(
                    managed: ["policy.deployment.mode": "typo"])),
            PolicyLoader.load(
                from: StaticPolicySource(
                    managed: ["policy.deployment.mode": "internalOnly"])),
        ]
        for policy in policies {
            let transport = RecordingTransport()
            let client = NetworkClient(policy: { policy }, transport: transport)
            await #expect(throws: NetworkFailure.self) { try await client.get(service: .iconAssets, url: url()) }
            #expect(await transport.calls.isEmpty)
        }
        #expect(throws: NetworkFailure(service: nil, reason: .unknownService)) {
            try NetworkAdmission.check(serviceID: "unknown?secret", destination: .url(url()), policy: .init())
        }
    }

    @Test func schemeAndLoopbackDistinctions() throws {
        var policy = NativePolicy.Network()
        for text in ["http://remote.example", "file:///tmp/icon", "https://user:pass@icons.example", "http://127.1"] {
            #expect(throws: NetworkFailure.self) {
                try NetworkAdmission.check(service: .iconAssets, destination: .url(url(text)), policy: policy)
            }
        }
        policy.mode = .airGapped
        policy.localIPC = true
        let local = try url("http://[::1]:8080/icon")
        policy.services[.iconAssets] = .init(enabled: true, origins: [try #require(NetworkOrigin(url: local))])
        try NetworkAdmission.check(service: .iconAssets, destination: .url(local), policy: policy)
        for text in [
            "http://127.0.0.1:8080/icon", "http://[::1]:8081/icon", "https://localhost/icon",
            "https://mirror.example/icon",
        ] {
            #expect(throws: NetworkFailure.self) {
                try NetworkAdmission.check(service: .iconAssets, destination: .url(url(text)), policy: policy)
            }
        }
        policy.localIPC = false
        #expect(throws: NetworkFailure(service: .iconAssets, reason: .localDenied)) {
            try NetworkAdmission.check(service: .iconAssets, destination: .url(local), policy: policy)
        }
    }

    @Test func restrictedMirrorAndUnconvertedConsumer() async throws {
        let policy = restricted()
        let transport = RecordingTransport(fail: true)
        let client = NetworkClient(policy: { policy }, transport: transport)
        await #expect(throws: NetworkFailure.self) {
            try await client.get(service: .iconAssets, url: url("https://mirror.example/a.svg"))
        }
        #expect(await transport.calls == [try url("https://mirror.example/a.svg")])
        var gap = policy.network
        gap.mode = .airGapped
        #expect(throws: NetworkFailure(service: .iconAssets, reason: .offMachineDenied)) {
            try NetworkAdmission.check(
                service: .iconAssets, destination: .url(url("https://mirror.example/a")), policy: gap)
        }
        var sdk = policy.network
        sdk.services[.nativeDiagnostics] = sdk.services[.iconAssets]
        #expect(throws: NetworkFailure(service: .nativeDiagnostics, reason: .integrationRequired)) {
            try NetworkAdmission.check(
                service: .nativeDiagnostics, destination: .url(url("https://mirror.example/a")), policy: sdk)
        }
    }

    @Test func redirectsRecheckBeforeFollowingAndValidateFinalOrigin() async throws {
        let transport = RecordingTransport(redirect: "https://denied.example/path?private=query")
        let client = NetworkClient(policy: { .default }, transport: transport)
        await #expect(throws: NetworkFailure(service: .iconAssets, reason: .redirectDenied)) {
            try await client.get(service: .iconAssets, url: url())
        }
        #expect(await transport.calls.count == 1)
        let final = RecordingTransport(finalURL: try url("https://unexpected.example/a"))
        let client2 = NetworkClient(policy: { .default }, transport: final)
        await #expect(throws: NetworkFailure(service: .iconAssets, reason: .finalOriginMismatch)) {
            try await client2.get(service: .iconAssets, url: url())
        }
        let same = RecordingTransport(redirect: "/redirected.svg")
        let client3 = NetworkClient(policy: { .default }, transport: same)
        let receipt = try await client3.get(service: .iconAssets, url: url())
        #expect(receipt.response.status == 200)
        #expect(await same.calls.count == 2)
    }

    @Test func revocationCancelsAndPreventsStalePublication() async throws {
        let box = PolicyBox()
        let transport = SuspendedTransport()
        let client = NetworkClient(policy: { box.value }, transport: transport)
        let task = Task { try await client.get(service: .iconAssets, url: url()) }
        await transport.waitUntilStarted()
        box.deny()
        client.policyDidChange()
        await transport.waitUntilCancelled()
        await transport.finish()
        await #expect(throws: NetworkFailure.self) { try await task.value }
        #expect(await transport.wasCancelled)

        let allowed = PolicyBox()
        let normal = NetworkClient(policy: { allowed.value }, transport: RecordingTransport())
        let receipt = try await normal.get(service: .iconAssets, url: url())
        var published = false
        allowed.deny()
        #expect(throws: NetworkFailure(service: .iconAssets, reason: .revoked)) {
            try normal.publish(receipt) { published = true }
        }
        #expect(!published)
    }

    @Test func callerCancellationAndSanitizedErrors() async throws {
        let transport = SuspendedTransport()
        let client = NetworkClient(policy: { .default }, transport: transport)
        let task = Task { try await client.get(service: .iconAssets, url: url()) }
        await transport.waitUntilStarted()
        task.cancel()
        await transport.waitUntilCancelled()
        await transport.finish()
        await #expect(throws: NetworkFailure(service: .iconAssets, reason: .cancelled)) { try await task.value }
        let failure = NetworkClient(policy: { .default }, transport: RecordingTransport(fail: true))
        do {
            _ = try await failure.get(service: .iconAssets, url: url())
            Issue.record("expected failure")
        } catch {
            #expect(String(describing: error) == "icons.assets:transportFailed")
        }
    }

    @Test func onlyExplicitCrossOriginRedirectsAreAllowed() async throws {
        let policy = PolicyLoader.load(
            from: StaticPolicySource(managed: [
                "policy.deployment.mode": "internalOnly",
                "policy.network": [
                    "services": [
                        "icons.assets": [
                            "enabled": true, "origins": ["https://icons.example", "https://cdn.internal.example:8443"],
                        ]
                    ]
                ],
            ]))
        let transport = RecordingTransport(redirect: "https://cdn.internal.example:8443/a.svg")
        let client = NetworkClient(policy: { policy }, transport: transport)
        let receipt = try await client.get(service: .iconAssets, url: url())
        #expect(try client.publish(receipt) { receipt.response.data } == Data("fixture".utf8))
        #expect(await transport.calls.count == 2)
        let deniedPort = RecordingTransport(redirect: "https://cdn.internal.example/a.svg")
        let deniedClient = NetworkClient(policy: { policy }, transport: deniedPort)
        await #expect(throws: NetworkFailure(service: .iconAssets, reason: .redirectDenied)) {
            try await deniedClient.get(service: .iconAssets, url: url())
        }
        #expect(await deniedPort.calls.count == 1)
        let credentialRedirect = RecordingTransport(redirect: "https://user:secret@icons.example/a.svg")
        let credentialClient = NetworkClient(policy: { .default }, transport: credentialRedirect)
        await #expect(throws: NetworkFailure(service: .iconAssets, reason: .invalidDestination)) {
            try await credentialClient.get(service: .iconAssets, url: url())
        }
        #expect(await credentialRedirect.calls.count == 1)
    }

    @Test func observedDenyThenRestoreStillRevokesOldWork() async throws {
        let updates = AsyncStream<NativePolicy>.makeStream()
        defer { updates.continuation.finish() }
        let transport = SuspendedTransport()
        let client = NetworkClient(policy: { .default }, updates: updates.stream, transport: transport)
        let task = Task { try await client.get(service: .iconAssets, url: url()) }
        await transport.waitUntilStarted()
        var denied = NativePolicy()
        denied.network.services[.iconAssets] = .init(enabled: false)
        updates.continuation.yield(denied)
        updates.continuation.yield(.default)
        await transport.waitUntilCancelled()
        await transport.finish()
        await #expect(throws: NetworkFailure(service: .iconAssets, reason: .revoked)) { try await task.value }
    }

    private func restricted() -> NativePolicy {
        PolicyLoader.load(
            from: StaticPolicySource(managed: [
                "policy.deployment.mode": "internalOnly",
                "policy.network": [
                    "services": [
                        "icons.assets": [
                            "enabled": true, "origins": ["https://mirror.example"],
                        ]
                    ]
                ],
            ]))
    }
}

private actor RecordingTransport: NetworkHTTPTransport {
    var calls: [URL] = []
    let redirect: String?
    let finalURL: URL?
    let fail: Bool
    init(redirect: String? = nil, finalURL: URL? = nil, fail: Bool = false) {
        self.redirect = redirect
        self.finalURL = finalURL
        self.fail = fail
    }
    func send(_ url: URL) async throws -> NetworkHTTPResponse {
        calls.append(url)
        if fail { throw URLError(.cannotConnectToHost, userInfo: [NSLocalizedDescriptionKey: "secret URL payload"]) }
        return .init(
            data: Data("fixture".utf8), status: redirect != nil && calls.count == 1 ? 302 : 200,
            url: finalURL ?? url, location: calls.count == 1 ? redirect : nil)
    }
}

private final class PolicyBox: @unchecked Sendable {
    private let lock = NSLock()
    private var policy = NativePolicy()
    var value: NativePolicy { lock.withLock { policy } }
    func deny() { lock.withLock { policy.network.services[.iconAssets] = .init(enabled: false) } }
}

private actor SuspendedTransport: NetworkHTTPTransport {
    private var response: CheckedContinuation<NetworkHTTPResponse, Never>?
    private var started: [CheckedContinuation<Void, Never>] = []
    private var cancelled: [CheckedContinuation<Void, Never>] = []
    private var url: URL?
    var wasCancelled = false
    func send(_ url: URL) async throws -> NetworkHTTPResponse {
        self.url = url
        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                response = continuation
                started.forEach { $0.resume() }
                started.removeAll()
            }
        } onCancel: {
            Task { await self.markCancelled() }
        }
    }
    func waitUntilStarted() async {
        if response != nil { return }
        await withCheckedContinuation { started.append($0) }
    }
    func waitUntilCancelled() async {
        if wasCancelled { return }
        await withCheckedContinuation { cancelled.append($0) }
    }
    private func markCancelled() {
        wasCancelled = true
        cancelled.forEach { $0.resume() }
        cancelled.removeAll()
    }
    func finish() {
        guard let url else { return }
        response?.resume(returning: .init(data: Data(), status: 200, url: url))
        response = nil
    }
}
