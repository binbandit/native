import Foundation
import NativeNetwork
import NativePolicy

@testable import Native

private let svg = Data("<svg viewBox=\"0 0 16 16\"><path d=\"M0 0 L16 0 L16 16 Z\"/></svg>".utf8)
private let index = Data("{\"agents\":[{\"id\":\"fixture\",\"icon\":\"https://assets.example/icon.svg\"}]}".utf8)

private actor FixtureTransport: NetworkHTTPTransport {
    var calls: [URL] = []
    var fail = false
    var suspended: CheckedContinuation<Void, Never>?
    var waitForStart: CheckedContinuation<Void, Never>?
    var pause = false
    func configure(fail: Bool = false, pause: Bool = false) { self.fail = fail; self.pause = pause }
    func send(_ url: URL) async throws -> NetworkHTTPResponse {
        calls.append(url)
        if pause {
            await withCheckedContinuation { continuation in
                suspended = continuation
                waitForStart?.resume()
                waitForStart = nil
            }
        }
        if fail { throw URLError(.notConnectedToInternet) }
        return .init(data: url.path.hasSuffix(".svg") ? svg : index, status: 200, url: url)
    }
    func started() async {
        if suspended != nil { return }
        await withCheckedContinuation { waitForStart = $0 }
    }
    func finish() { suspended?.resume(); suspended = nil }
}

private final class FixturePolicy: @unchecked Sendable {
    private let lock = NSLock()
    private var policy: NativePolicy
    init(_ policy: NativePolicy = .default) { self.policy = policy }
    var current: NativePolicy { lock.withLock { policy } }
    func set(_ value: NativePolicy) { lock.withLock { policy = value } }
}

@main struct EnterpriseNetworkHarness {
    static func require(_ condition: Bool, _ message: String) {
        guard condition else { fatalError(message) }
    }

    static func denied() -> NativePolicy {
        PolicyLoader.load(
            from: StaticPolicySource(managed: [
                "policy.network": [
                    "services": [
                        "icons.index": ["enabled": false], "icons.assets": ["enabled": false],
                    ]
                ]
            ]))
    }

    static func main() async throws {
        let root = URL(filePath: CommandLine.arguments[1], directoryHint: .isDirectory)
        let policy = FixturePolicy(denied())
        let transport = FixtureTransport()
        let network = NetworkClient(policy: { policy.current }, transport: transport)
        let registry = AgentIconRegistry(directory: root, network: network)
        require(await registry.icon(for: "fixture") == nil, "denied cache miss must use fallback")
        require(await transport.calls.isEmpty, "denied miss reached resolver/transport")

        let assetsDenied = PolicyLoader.load(
            from: StaticPolicySource(managed: [
                "policy.network": [
                    "services": [
                        "icons.assets": ["enabled": false]
                    ]
                ]
            ]))
        policy.set(assetsDenied)
        network.policyDidChange()
        require(await registry.icon(for: "fixture") == nil, "asset denial must skip index fetch")
        require(await transport.calls.isEmpty, "asset denial still fetched the index")
        policy.set(denied())
        network.policyDidChange()

        // Cached index URLs must be checked again under today's policy.
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let indexFile = root.appending(path: "registry.json")
        try index.write(to: indexFile)
        try FileManager.default.setAttributes([.modificationDate: Date.distantPast], ofItemAtPath: indexFile.path)
        policy.set(
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
                ])))
        network.policyDidChange()
        let staleRegistry = AgentIconRegistry(directory: root, network: network)
        require(await staleRegistry.icon(for: "fixture") == nil, "stale index bypassed policy")
        require(await transport.calls.isEmpty, "stale cache made a denied request")

        policy.set(.default)
        network.policyDidChange()
        require(await staleRegistry.icon(for: "fixture") == svg, "permitted fetch failed")
        let count = await transport.calls.count
        require(count == 2, "expected index plus SVG fetch")
        let freshRegistry = AgentIconRegistry(directory: root, network: network)
        require(await freshRegistry.icon(for: "fixture") == svg, "cached SVG missing")
        require(await transport.calls.count == count, "fresh cache fetched again")

        policy.set(denied())
        network.policyDidChange()
        let cachedFile = root.appending(path: "icons/fixture.svg")
        try FileManager.default.setAttributes([.modificationDate: Date.distantPast], ofItemAtPath: cachedFile.path)
        require(await freshRegistry.icon(for: "fixture") == svg, "denial discarded cached SVG")
        // Explicit miss waits for the shared index load and exercises the same refresh admission.
        require(await freshRegistry.icon(for: "missing") == nil, "missing id unexpectedly resolved")
        require(await transport.calls.count == count, "stale refresh bypassed denial")

        // An explicit mirror with a failed load cannot use a public cached index as fallback.
        let mirrorPolicy = PolicyLoader.load(
            from: StaticPolicySource(managed: [
                "policy.network": [
                    "services": [
                        "icons.index": [
                            "enabled": true, "origins": ["https://mirror.example"],
                            "endpoint": "https://mirror.example/registry.json",
                        ]
                    ]
                ]
            ]))
        policy.set(mirrorPolicy)
        network.policyDidChange()
        await transport.configure(fail: true)
        try FileManager.default.removeItem(at: cachedFile)
        let mirrorRegistry = AgentIconRegistry(directory: root, network: network)
        require(await mirrorRegistry.icon(for: "fixture") == nil, "failed mirror should fall back locally")
        require(await transport.calls.count == count + 1, "mirror failure retried/fell back")
        require(await transport.calls.last?.host == "mirror.example", "mirror was not selected")

        // A late transport that ignores cancellation must not publish or cache the SVG.
        let raceRoot = root.appending(path: "race")
        try FileManager.default.createDirectory(at: raceRoot, withIntermediateDirectories: true)
        try index.write(to: raceRoot.appending(path: "registry.json"))
        let racePolicy = FixturePolicy()
        let raceTransport = FixtureTransport()
        await raceTransport.configure(pause: true)
        let raceNetwork = NetworkClient(policy: { racePolicy.current }, transport: raceTransport)
        let raceRegistry = AgentIconRegistry(directory: raceRoot, network: raceNetwork)
        let task = Task { await raceRegistry.icon(for: "fixture") }
        await raceTransport.started()
        racePolicy.set(denied())
        raceNetwork.policyDidChange()
        await raceTransport.finish()
        require(await task.value == nil, "revoked response published")
        require(
            !FileManager.default.fileExists(atPath: raceRoot.appending(path: "icons/fixture.svg").path),
            "revoked response was cached")
        print(
            "enterprise-network: denial, stale index/refresh, permitted fetch/cache, mirror isolation and revocation passed"
        )
    }
}
