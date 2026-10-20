#if DEBUG
import ACP
import Foundation
import NativeHostClient
import NativeHostProtocol
import Observation

/// Made-up hosts in every state, for previews and for checking Settings ▸ Hosts in a running app
/// without paired machines: `-NativeHostsFixtures all` (every state), `empty` (This Mac alone),
/// `signin` (one host whose agents want signing in) or `components` (the device picker and badges).
/// Development builds only; off by default.
/// Actions change the fixtures the way the real hosts would, after a moment.
@Observable
final class HostsFixtureDirectory: HostsDirectory {
    enum Scenario: String {
        case all, empty, signin
        /// The picker and badges instead of the page (`HostsComponentsFixturePage`).
        case components
    }

    private(set) var hosts: [HostDisplay]
    let problem: String? = nil
    let canAddHost = true

    static let defaultsKey = "NativeHostsFixtures"

    /// The scenario the launch argument asks for, or nil when it's off.
    static var scenario: Scenario? {
        UserDefaults.standard.string(forKey: defaultsKey).flatMap(Scenario.init(rawValue:))
    }

    init(_ scenario: Scenario) {
        hosts = Self.hosts(for: scenario)
    }

    func addHost() {}

    func rename(_ host: RemoteHostID, to name: String) {
        update(.remote(host)) { display in
            let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
            let machine = display.machineName ?? display.name
            display.name = trimmed.isEmpty ? machine : trimmed
            display.machineName = display.name == machine ? nil : machine
        }
    }

    func setLook(_ look: HostLook, for device: SessionDevice) {
        update(device) { $0.look = look }
    }

    func remove(_ host: RemoteHostID) -> (() -> Void)? {
        guard let index = hosts.firstIndex(where: { $0.device == .remote(host) }) else { return nil }
        let removed = hosts.remove(at: index)
        return { [weak self] in self?.hosts.insert(removed, at: min(index, self?.hosts.count ?? 0)) }
    }

    func reconnect(_ host: RemoteHostID) {
        update(.remote(host)) { $0.state = .connecting }
        after(.seconds(2)) { $0.update(.remote(host)) { $0.state = .online } }
    }

    func setKeepAwake(_ mode: KeepAwakeMode, on device: SessionDevice) async throws {
        try await Task.sleep(for: .seconds(0.5))
        update(device) { display in
            display.keepAwakeMode = mode
            display.machine.keepAwake =
                switch mode {
                case .on: "Stays awake"
                case .whileAgentsWork: "Awake while agents work"
                case .off, .unknown: "May sleep"
                }
        }
    }

    func doctorClient(for device: SessionDevice) -> NativeHostClient? {
        nil
    }

    func signIn(
        _ agent: AgentDefinition.ID, on device: SessionDevice, with method: AuthMethod, apiKey: String?
    )
        async throws
    {
        let kind = HostSignInMethod(method, agent: Self.agent(agent.rawValue))?.kind
        updateAgent(agent, on: device) { $0.isSigningIn = true }
        defer { updateAgent(agent, on: device) { $0.isSigningIn = false } }
        if kind == .link {
            // Waits at the link until Check Again or Cancel, as a real link sign-in waits on the user.
            updateAgent(agent, on: device) { display in
                display.signInLink = URL(string: "https://auth.example.com/codex/device").map {
                    HostSignInLink(
                        url: $0, code: "WDJB-MJHT",
                        message: "Sign in to ChatGPT at auth.example.com/codex/device and enter this code: WDJB-MJHT")
                }
            }
            while hosts.first(where: { $0.device == device })?.agents.first(where: { $0.id == agent })?.signInLink
                != nil
            {
                try await Task.sleep(for: .milliseconds(200))
            }
            if cancelled.remove(agent) != nil { throw FixtureFailure.cancelled }
            return
        }
        try await Task.sleep(for: .seconds(1.5))
        if apiKey?.hasPrefix("bad") == true { throw FixtureFailure.keyRejected }
        updateAgent(agent, on: device) { display in
            display.needsSignIn = false
            display.isSignedIn = true
            display.signInLabel = apiKey == nil ? "ChatGPT Pro · you@example.com" : "OpenAI API key"
            if apiKey != nil { display.savedKeys.insert(method.id) }
        }
    }

    func removeAPIKey(_ agent: AgentDefinition.ID, on device: SessionDevice, for method: AuthMethod) async throws {
        try await Task.sleep(for: .seconds(0.5))
        updateAgent(agent, on: device) { display in
            display.savedKeys.remove(method.id)
            display.isSignedIn = false
            display.signInLabel = "Not logged in"
        }
    }

    func cancelSignIn(_ agent: AgentDefinition.ID, on device: SessionDevice) async {
        cancelled.insert(agent)
        updateAgent(agent, on: device) { $0.signInLink = nil }
    }

    func checkAgain(_ agent: AgentDefinition.ID, on device: SessionDevice) async throws {
        try await Task.sleep(for: .seconds(1))
        if device == .remote(HostDeviceFixtures.mini), agent.rawValue == "cursor" {
            throw FixtureFailure.busy
        }
        updateAgent(agent, on: device) { display in
            if case .notInstalled = display.status {
                display.status = .ready
            } else if display.wantsSignIn {
                display.needsSignIn = false
                display.isSignedIn = true
                display.signInLabel = "ChatGPT Pro · you@example.com"
                display.signInLink = nil
            }
        }
    }

    /// Link sign-ins the user cancelled, so the waiting `signIn` fails as a real one would.
    @ObservationIgnored private var cancelled: Set<AgentDefinition.ID> = []

    private enum FixtureFailure: LocalizedError {
        case keyRejected, cancelled, busy

        var errorDescription: String? {
            switch self {
            case .keyRejected: "Codex turned the key away: it isn't a valid OpenAI API key. Nothing was saved."
            case .cancelled: "You cancelled signing in."
            case .busy:
                "Cursor is working on 2 tasks on Mac mini. Check again when they finish, or stop them."
            }
        }
    }

    // MARK: - Changing fixtures

    private func update(_ device: SessionDevice, _ change: (inout HostDisplay) -> Void) {
        guard let index = hosts.firstIndex(where: { $0.device == device }) else { return }
        change(&hosts[index])
    }

    private func updateAgent(
        _ agent: AgentDefinition.ID, on device: SessionDevice, _ change: (inout HostAgentDisplay) -> Void
    ) {
        update(device) { host in
            guard let index = host.agents.firstIndex(where: { $0.id == agent }) else { return }
            change(&host.agents[index])
        }
    }

    private func after(_ delay: Duration, _ change: @escaping (HostsFixtureDirectory) -> Void) {
        Task { [weak self] in
            try? await Task.sleep(for: delay)
            if let self { change(self) }
        }
    }

    // MARK: - The fixtures

    private static func hosts(for scenario: Scenario) -> [HostDisplay] {
        switch scenario {
        case .empty, .components: [thisMac]
        case .signin: [thisMac, mini]
        case .all: [thisMac, mini, studio, buildBox, linux, oldMini]
        }
    }

    private static let now = Date.now

    private static var thisMac: HostDisplay {
        HostDisplay(
            device: .thisMac, name: "This Mac", machineName: "MacBook Pro",
            look: HostLook(symbol: .laptop, tint: .graphite), state: .online,
            machine: HostMachineSummary(
                system: "macOS 26.1", nativeVersion: "1.4.2 (212)", bootedAt: now.addingTimeInterval(-2 * 86_400),
                loadAverage: 2.41),
            agents: [
                HostAgentDisplay(agent: agent("claude-code"), status: .ready),
                HostAgentDisplay(agent: agent("codex"), status: .ready),
                HostAgentDisplay(agent: agent("cursor"), status: .idle),
            ])
    }

    private static var mini: HostDisplay {
        let codex = agent("codex")
        let cursor = agent("cursor")
        return HostDisplay(
            device: .remote(HostDeviceFixtures.mini), name: "Mac mini", machineName: "Home Mac mini",
            look: HostLook(symbol: .mini, tint: .cobalt), state: .online,
            machine: HostMachineSummary(
                system: "macOS 26.1", nativeVersion: "1.4.2 (212)", bootedAt: now.addingTimeInterval(-9 * 86_400),
                loadAverage: 0.42, keepAwake: "Awake while agents work"),
            agents: [
                HostAgentDisplay(
                    agent: agent("claude-code"), status: .ready, signInLabel: "Claude Max · you@example.com",
                    isSignedIn: true, terminalSignIn: "claude"),
                HostAgentDisplay(
                    agent: codex, status: .ready, needsSignIn: true, signInLabel: "Not logged in", isSignedIn: false,
                    methods: [
                        AuthMethod(id: "chatgpt", name: "ChatGPT", description: "Sign in with your ChatGPT plan."),
                        AuthMethod(
                            id: "chatgpt-device-code", name: "ChatGPT (device code)",
                            description: "Open a page on any device and enter a code.", kind: .link),
                        AuthMethod(
                            id: "openai-api-key", name: "OpenAI API key",
                            kind: .environment([AuthMethod.Variable(name: "OPENAI_API_KEY", label: "API key")]),
                            credentialsPage: URL(string: "https://platform.openai.com/api-keys")),
                    ].compactMap { HostSignInMethod($0, agent: codex) },
                    installCommand: codex.manifest.setup?.install, docs: codex.manifest.setup?.docs),
                HostAgentDisplay(
                    agent: cursor, status: .ready, needsSignIn: true,
                    methods: [AuthMethod(id: "cursor_login", name: "Log in with Cursor")].compactMap {
                        HostSignInMethod($0, agent: cursor)
                    },
                    installCommand: cursor.manifest.setup?.install, docs: cursor.manifest.setup?.docs),
                HostAgentDisplay(
                    agent: agent("opencode"), status: .notInstalled(command: "opencode"),
                    installCommand: "npm install -g opencode-ai"),
            ],
            sessions: HostSessionCounts(total: 3, working: 1), sshDestination: "192.168.1.24",
            keepAwakeMode: .whileAgentsWork)
    }

    private static var studio: HostDisplay {
        HostDisplay(
            device: .remote(HostDeviceFixtures.studio), name: "Studio", look: HostLook(symbol: .studio, tint: .prism),
            state: .connecting, sessions: HostSessionCounts(total: 1), sshDestination: "100.84.12.7")
    }

    private static var buildBox: HostDisplay {
        HostDisplay(
            device: .remote(HostDeviceFixtures.buildBox), name: "build-box",
            look: HostLook(symbol: .server, tint: .fern),
            state: .offline(
                reason: "Nothing answered at 192.168.1.40 or 100.84.3.9 for 2 minutes.",
                lastConnected: now.addingTimeInterval(-3 * 3600)),
            sessions: HostSessionCounts(total: 2, working: 0), sshDestination: "192.168.1.40")
    }

    private static var linux: HostDisplay {
        HostDisplay(
            device: .remote(HostDeviceFixtures.linux), name: "linux-01", look: HostLook(symbol: .pc, tint: .ember),
            state: .needsUpdate(
                message: "Runs Native 1.3.0, which is older than this Mac's. Update Native on linux-01."),
            machine: HostMachineSummary(system: "Ubuntu 24.04", nativeVersion: "1.3.0 (188)"),
            sshDestination: "100.84.20.2")
    }

    private static var oldMini: HostDisplay {
        HostDisplay(
            device: .remote(RemoteHostID(UUID(uuid: (5, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 5)))),
            name: "Office mini", look: HostLook(symbol: .mini, tint: .glass),
            state: .pairingEnded(reason: "Office mini removed this Mac from its paired devices."))
    }

    /// The built-in agent with `id`, so fixtures show real names and icons.
    static func agent(_ id: String) -> AgentDefinition {
        let manifests = BuiltInPlugins.all.flatMap { plugin in
            plugin.manifest.agents.map { (agent: $0, pluginID: plugin.manifest.id) }
        }
        guard let found = manifests.first(where: { $0.agent.id == id }) else {
            return AgentDefinition(AgentManifest(id: id, name: id.capitalized, command: id), pluginID: "fixtures")
        }
        return AgentDefinition(found.agent, pluginID: found.pluginID)
    }
}
#endif
