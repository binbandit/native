import Foundation
import NativePolicy

@testable import Native

/// A managed source the harness edits, standing in for a configuration profile being installed,
/// changed or removed.
private final class FixtureSource: PolicySource, @unchecked Sendable {
    private let lock = NSLock()
    private var managed: [String: Any]
    let enrollment: (any PolicyEnrollmentStore)?

    init(_ managed: [String: Any] = [:], enrollment: (any PolicyEnrollmentStore)? = nil) {
        self.managed = managed
        self.enrollment = enrollment
    }

    func set(_ values: [String: Any]) { lock.withLock { managed = values } }
    func managedEntry(forKey key: String) -> ManagedEntry {
        lock.withLock { managed[key].map(ManagedEntry.value) ?? .absent }
    }
    func userValue(forKey key: String) -> Any? { nil }
    var managedKeys: [String]? { lock.withLock { Array(managed.keys) } }
}

/// Every prepare and event a fixture plugin receives, with a gate to hold one prepare open.
private actor Calls {
    private(set) var prepared: [String] = []
    private(set) var handled: [String] = []
    private var held: String?
    private var release: CheckedContinuation<Void, Never>?
    private var started: CheckedContinuation<Void, Never>?

    func hold(_ id: String) { held = id }

    func prepare(_ id: String) async {
        prepared.append(id)
        guard id == held else { return }
        started?.resume()
        started = nil
        await withCheckedContinuation { release = $0 }
    }

    func handle(_ id: String) { handled.append(id) }

    func waitUntilHeldStarts() async {
        guard let held, !prepared.contains(held) else { return }
        await withCheckedContinuation { started = $0 }
    }

    func finishHeld() {
        release?.resume()
        release = nil
        held = nil
    }

    func reset() {
        prepared = []
        handled = []
    }
}

/// A code plugin, with or without a capability declaration.
private struct RecordingPlugin: NativePlugin {
    let manifest: PluginManifest
    let capabilities: Set<PolicyCapability>?
    let calls: Calls

    init(_ id: String, capabilities: Set<PolicyCapability>?, calls: Calls) {
        manifest = PluginManifest(id: id, name: id)
        self.capabilities = capabilities
        self.calls = calls
    }

    func prepareForLaunch() async { await calls.prepare(manifest.id) }
    func handle(_ event: SessionEvent) async { await calls.handle(manifest.id) }
}

@main struct EnterprisePolicyHarness {
    static func require(_ condition: Bool, _ message: String) {
        guard condition else { fatalError(message) }
    }

    static func manifestJSON(_ id: String, agent: Bool) -> Data {
        let contribution =
            agent
            ? #""agents": [{"id": "\#(id)-agent", "name": "Fixture", "command": "/usr/bin/false"}]"#
            : #""commandKnowledge": {"version": 1, "programs": [], "locations": []}"#
        return Data(#"{"id": "\#(id)", "name": "Fixture", \#(contribution)}"#.utf8)
    }

    static let internalOnly = "internalOnly"

    @MainActor static func main() async throws {
        let work = URL(filePath: CommandLine.arguments[1], directoryHint: .isDirectory)
        require(
            PluginRegistry.directory.path().hasPrefix(work.path()), "run with -pluginsDirectory inside the work folder")
        // Installed manifests, mirroring two built-in ones below.
        for (id, agent) in [("fixture.disk-agent", true), ("fixture.disk-knowledge", false)] {
            let folder = PluginRegistry.directory.appending(path: id, directoryHint: .isDirectory)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try manifestJSON(id, agent: agent).write(to: folder.appending(path: "plugin.json"))
        }
        let calls = Calls()
        let builtIns: [any NativePlugin] = [
            RecordingPlugin("fixture.undeclared", capabilities: nil, calls: calls),
            RecordingPlugin("fixture.declared", capabilities: [.pluginAppearance], calls: calls),
            RecordingPlugin("fixture.declared-next", capabilities: [.pluginAppearance], calls: calls),
            ManifestPlugin(
                manifest: try JSONDecoder().decode(
                    PluginManifest.self, from: manifestJSON("fixture.agent", agent: true))),
            ManifestPlugin(
                manifest: try JSONDecoder().decode(
                    PluginManifest.self, from: manifestJSON("fixture.knowledge", agent: false))),
        ]
        var suites: [String] = []
        defer { suites.forEach { UserDefaults().removePersistentDomain(forName: $0) } }
        func registry(_ center: PolicyCenter) -> PluginRegistry {
            let suite = "enterprise-policy-harness.\(UUID().uuidString)"
            suites.append(suite)
            return PluginRegistry(
                builtIns: builtIns, defaults: UserDefaults(suiteName: suite) ?? .standard, policyCenter: center)
        }
        let event = SessionEvent.needsUser(nil, reason: "fixture")
        let everyPlugin: Set = [
            "fixture.undeclared", "fixture.declared", "fixture.declared-next", "fixture.agent", "fixture.knowledge",
            "fixture.disk-agent", "fixture.disk-knowledge",
        ]

        // Ordinary mode: today's behavior, every plugin prepared and told.
        do {
            let center = PolicyCenter(source: FixtureSource())
            let plugins = registry(center)
            let prepared = await plugins.prepareForLaunch()
            require(everyPlugin.isSubset(of: prepared), "ordinary mode skipped a plugin: \(prepared)")
            require(
                prepared.isSuperset(of: ["native.policy", "native.telemetry", "native.task-scripts"]), "system plugins")
            await plugins.broadcast(event)
            require(
                Set(await calls.handled) == ["fixture.undeclared", "fixture.declared", "fixture.declared-next"],
                "ordinary events")
            require(
                Set(plugins.agents.map(\.id.rawValue)) == ["fixture.agent-agent", "fixture.disk-agent-agent"], "agents")
            await calls.reset()
        }

        // Restricted: the organization lists every fixture, built in or not.
        let listed: [String: Any] = [
            "policy.deployment.mode": internalOnly, "policy.plugins.allowed": Array(everyPlugin),
        ]
        do {
            let center = PolicyCenter(source: FixtureSource(listed))
            let plugins = registry(center)
            // The user's choice and the plugin's default can't bring back what policy denies.
            plugins.setEnabled(true, for: "fixture.undeclared")
            let prepared = await plugins.prepareForLaunch()
            require(
                prepared == [
                    "fixture.declared", "fixture.declared-next", "fixture.knowledge", "fixture.disk-knowledge",
                    "native.policy",
                ],
                "restricted admission: \(prepared)")
            let declared = ["fixture.declared", "fixture.declared-next"]
            require(await calls.prepared == declared, "denied plugins were prepared: \(await calls.prepared)")
            await plugins.broadcast(event)
            require(await calls.handled == declared, "denied plugins heard an event")
            require(
                plugins.agents.isEmpty && plugins.agent(.init(rawValue: "fixture.agent-agent")) == nil,
                "agents launchable")
            require(
                !plugins.isEnabled("fixture.undeclared") && !plugins.isAllowed("fixture.agent"), "denied plugin enabled"
            )
            // A built-in manifest and the same manifest from disk get the same decision.
            func reason(_ id: String) -> PluginAdmission? {
                plugins.plugins.first { $0.id == id }.map(plugins.admission(of:))
            }
            require(reason("fixture.agent") == reason("fixture.disk-agent"), "agent manifest parity")
            require(
                reason("fixture.agent")?.reason == .capability(.agentExecution, .notSupportedInRestrictedMode),
                "agent manifest reason")
            require(reason("fixture.knowledge") == reason("fixture.disk-knowledge"), "knowledge manifest parity")
            require(reason("fixture.undeclared")?.reason == .undeclared, "undeclared reason")
            await calls.reset()
        }

        // Revocation while a plugin prepares: it isn't counted, and the next one never starts.
        do {
            let source = FixtureSource(listed)
            let center = PolicyCenter(source: source)
            let plugins = registry(center)
            await calls.hold("fixture.declared")
            let preparing = Task { await plugins.prepareForLaunch() }
            await calls.waitUntilHeldStarts()
            source.set(["policy.deployment.mode": internalOnly, "policy.plugins.allowed": [String]()])
            center.reload()
            await calls.finishHeld()
            let prepared = await preparing.value
            require(prepared == ["native.policy"], "revoked plugin counted as prepared: \(prepared)")
            require(await calls.prepared == ["fixture.declared"], "a revoked plugin was prepared afterwards")
            require(!plugins.enabledPlugins.contains { $0.manifest.id == "fixture.declared" }, "revoked plugin active")
            await plugins.broadcast(event)
            require(await calls.handled.isEmpty, "revoked plugin heard an event")
            await calls.reset()
        }

        // Malformed managed allowlist: installed plugins are denied, never allowed by default.
        do {
            let center = PolicyCenter(source: FixtureSource(["policy.plugins.allowed": "fixture.disk-knowledge"]))
            let plugins = registry(center)
            let prepared = await plugins.prepareForLaunch()
            require(
                !prepared.contains("fixture.disk-knowledge") && !prepared.contains("fixture.disk-agent"),
                "malformed list")
            require(prepared.contains("fixture.declared"), "ordinary built-ins keep today's rule")
            require(center.policy.deployment.state == .invalid, "malformed state")
            await calls.reset()
        }

        // Profile removal and restart: still restricted, everything optional denied, until the
        // organization deploys ordinary mode.
        do {
            let store = MemoryPolicyEnrollmentStore()
            _ = PolicyCenter(source: FixtureSource(listed, enrollment: store))
            let source = FixtureSource([:], enrollment: store)
            let restarted = PolicyCenter(source: source)
            let plugins = registry(restarted)
            require(restarted.policy.deployment.lockdown == .removedAfterEnrollment, "removal re-entered ordinary mode")
            require(await plugins.prepareForLaunch() == ["native.policy"], "removed profile admitted a plugin")
            require(await calls.prepared.isEmpty, "removed profile prepared a plugin")
            source.set(["policy.deployment.mode": "ordinary"])
            restarted.reload()
            require(store.load() == nil && !restarted.policy.isRestricted, "ordinary mode didn't release enrollment")
            require(everyPlugin.isSubset(of: await plugins.prepareForLaunch()), "released policy kept plugins off")
            await calls.reset()
        }

        print(
            "enterprise-policy harness: ordinary, restricted, parity, revocation, malformed and removal checks passed")
    }
}
