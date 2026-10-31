import ACP
import ApprovalAnalysis
import Experiments
import Foundation
import NativeHostProtocol
import NativePolicy
import Observation
import Search
import SessionTools
import os

/// The plugins Native runs with: the built-in ones plus any manifests in `~/.native/plugins`, each on
/// or off by the user's choice, or by its default until they choose. Everything else asks this for
/// agents, MCP servers, titles and hooks.
@Observable
final class PluginRegistry {
    struct LoadedPlugin: Identifiable {
        enum Source: Hashable {
            case builtIn
            case manifest(URL)
        }

        let plugin: any NativePlugin
        let source: Source
        /// Kept, since reading it through the plugin copies the whole manifest.
        let id: String
        /// Whether experiments can change it, worked out once: finding out scans every setting of
        /// the manifest for placeholders.
        let usesExperiments: Bool

        init(plugin: any NativePlugin, source: Source) {
            self.plugin = plugin
            self.source = source
            id = plugin.manifest.id
            usesExperiments = (plugin as? ManifestPlugin)?.manifest.usesExperiments ?? false
        }
    }

    struct LoadFailure: Identifiable, Hashable {
        let url: URL
        let message: String

        var id: URL { url }
    }

    /// `~/.native/plugins`, unless the `pluginsDirectory` default names another folder: launch with
    /// `-pluginsDirectory <path>` to try plugins without touching the user's own.
    static let directory =
        UserDefaults.standard.string(forKey: "pluginsDirectory").map { URL(filePath: $0, directoryHint: .isDirectory) }
        ?? URL.homeDirectory.appending(
            path: ".native/plugins", directoryHint: .isDirectory)

    /// Every loaded plugin, as its experiments leave it (`PluginExperimentSet`).
    var plugins: [LoadedPlugin] {
        contributions.plugins
    }
    /// What's wrong with enabled plugins' experiments, for Labs.
    private(set) var experimentProblems: [PluginExperimentProblem] = []
    private var loadedPlugins: [LoadedPlugin] = []
    private(set) var failures: [LoadFailure] = []
    /// The user's explicit on/off choices; a plugin without one follows `isEnabledByDefault`.
    private var choices: [String: Bool]
    private var nativeMCPChoices: [String: Bool] = [:]

    private let defaults: UserDefaults
    private let builtIns: [any NativePlugin]
    /// The organization's policy, which admits every plugin before it contributes or runs.
    let policyCenter: PolicyCenter
    @ObservationIgnored private var policyWatch: Task<Void, Never>?
    private let logger = Logger(subsystem: "Native", category: "Plugins")
    private static let choicesKey = "pluginChoices"
    /// Before plugins had defaults, only turning one off was recorded.
    private static let legacyDisabledKey = "disabledPlugins"

    init(
        builtIns: [any NativePlugin] = BuiltInPlugins.all, defaults: UserDefaults = .standard,
        policyCenter: PolicyCenter = .shared
    ) {
        self.builtIns = builtIns
        self.defaults = defaults
        self.policyCenter = policyCenter
        nativeMCPChoices = defaults.dictionary(forKey: "nativeMCPChoices") as? [String: Bool] ?? [:]
        if let stored = defaults.dictionary(forKey: Self.choicesKey) as? [String: Bool] {
            choices = stored
        } else {
            let disabled = defaults.stringArray(forKey: Self.legacyDisabledKey) ?? []
            choices = Dictionary(uniqueKeysWithValues: disabled.map { ($0, false) })
        }
        reload()
        // A plugin the organization revokes takes its experiments out of Labs straight away.
        policyWatch = Task { [weak self, policyCenter] in
            for await _ in Observations({ policyCenter.policy }) {
                guard let self else { return }
                self.syncExperiments()
            }
        }
    }

    isolated deinit {
        policyWatch?.cancel()
    }

    #if DEBUG
    /// Inert contributions for previews: no plugin folder reads or shared experiment mutations.
    init(previewing plugins: [any NativePlugin], disabled: Set<String> = []) {
        builtIns = plugins
        defaults = PreviewUserDefaults()
        policyCenter = .shared
        choices = Dictionary(uniqueKeysWithValues: disabled.map { ($0, false) })
        loadedPlugins = plugins.map { LoadedPlugin(plugin: $0, source: .builtIn) }
    }
    #endif

    /// Reads the plugins folder again. Built-ins come first, so their ids can't be taken over.
    func reload() {
        var loaded = builtIns.map { LoadedPlugin(plugin: $0, source: .builtIn) }
        var failures: [LoadFailure] = []
        let folders =
            (try? FileManager.default.contentsOfDirectory(
                at: Self.directory, includingPropertiesForKeys: nil, options: .skipsHiddenFiles)) ?? []
        for folder in folders.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
            let url = folder.appending(path: "plugin.json")
            do {
                let manifest = try JSONDecoder().decode(PluginManifest.self, from: Data(contentsOf: url))
                try validate(manifest, against: loaded)
                loaded.append(LoadedPlugin(plugin: ManifestPlugin(manifest: manifest), source: .manifest(url)))
            } catch {
                logger.error("Skipping plugin at \(url.path(percentEncoded: false), privacy: .public): \(error)")
                failures.append(LoadFailure(url: url, message: Self.describe(error)))
            }
        }
        loadedPlugins = loaded
        self.failures = failures
        syncExperiments()
    }

    func isEnabled(_ id: String) -> Bool {
        guard isAllowed(id) else { return false }
        return choices[id] ?? loadedPlugins.first { $0.id == id }?.plugin.isEnabledByDefault ?? true
    }

    /// Whether the organization lets the plugin load (`admission(of:)`), and its own feature gate
    /// agrees (`NativePlugin.isAllowed(by:)`).
    func isAllowed(_ id: String) -> Bool {
        guard let loaded = loadedPlugins.first(where: { $0.id == id }) else {
            return policyCenter.policy.admission(ofPlugin: id, origin: .installed, capabilities: nil).isAdmitted
        }
        return loaded.plugin.isAllowed(by: policyCenter.policy) && admission(of: loaded).isAdmitted
    }

    /// Whether the user has switched the plugin on or off themselves, rather than it following its default.
    func hasChoice(for id: String) -> Bool {
        choices[id] != nil
    }

    /// Records the user's choice, which then outlasts any change to the plugin's default.
    func setEnabled(_ enabled: Bool, for id: String) {
        choices[id] = enabled
        defaults.set(choices, forKey: Self.choicesKey)
        syncExperiments()
    }

    func nativeMCPChoice(for agent: AgentDefinition.ID) -> Bool? {
        nativeMCPChoices[agent.rawValue]
    }

    func nativeMCPEnabled(for agent: AgentDefinition) -> Bool {
        nativeMCPChoice(for: agent.id) ?? (agent.manifest.nativeSkill == nil || agent.manifest.nativeSkill == .unknown)
    }

    func setNativeMCPEnabled(_ enabled: Bool, for agent: AgentDefinition.ID) {
        nativeMCPChoices[agent.rawValue] = enabled
        defaults.set(nativeMCPChoices, forKey: "nativeMCPChoices")
    }

    /// Hands enabled plugins' experiments to Labs, so a plugin's experiments and their claims come
    /// and go with it.
    private func syncExperiments() {
        let set = PluginExperimentSet(
            plugins: loadedPlugins.filter { isEnabled($0.id) }.map(\.plugin),
            reserved: Set(ExperimentCatalog.native.experiments.map(\.id))
        )
        experimentProblems = set.problems
        ExperimentStore.shared.setContributedExperiments(set.descriptors)
    }

    // MARK: - Contributions of enabled plugins

    /// Enabled plugins, plus the system plugins policy admits (`SystemPlugins`).
    var enabledPlugins: [any NativePlugin] {
        contributions.enabledPlugins
    }

    /// Enabled plugins' task tools, each named for its plugin. One that would take another's id or
    /// the workbench is left out (`SessionToolSpec.isAllowed(fromPlugin:)`).
    var sessionTools: [SessionToolContribution] {
        enabledPlugins.flatMap { plugin in
            plugin.sessionTools.filter { $0.spec.isAllowed(fromPlugin: plugin.manifest.id) }.map { tool in
                var tool = tool
                tool.pluginName = plugin.manifest.name
                return tool
            }
        }
    }

    /// Validated descriptions from shipped data, policy and enabled plugins.
    var commandKnowledge: CommandKnowledge { contributions.commandKnowledge }

    /// Agents of enabled plugins that the organization allows, with any environment it adds.
    var agents: [AgentDefinition] {
        contributions.agents
    }

    func agent(_ id: AgentDefinition.ID) -> AgentDefinition? {
        agents.first { $0.id == id }
    }

    /// Every MCP server enabled plugins want the agent to have for this session.
    func mcpServers(for session: SessionContext) -> [MCPServer] {
        guard policyCenter.policy.decision(for: .mcpExecution).isPermitted else { return [] }
        // The organization's blocks and allowlist apply to every server but the ones it requires.
        let policy = policyCenter.policy.mcp
        let required = Set(policy.required.map(\.name))
        return enabledPlugins.flatMap { plugin in
            plugin.manifest.mcpServers.compactMap(\.server) + plugin.mcpServers(for: session)
        }
        .filter {
            required.contains($0.policyName) || policy.allows(name: $0.policyName, command: $0.policyCommandLine)
        }
    }

    // MARK: - Session policy

    /// What enabled plugins want left out of this session, merged.
    func sessionPolicy(for session: SessionContext) -> SessionPolicy {
        enabledPlugins.reduce(.none) { $0.merging($1.sessionPolicy(for: session)) }
    }

    /// What enabled plugins want left out of every session of `agent`, merged.
    func launchPolicy(for agent: AgentDefinition.ID) -> SessionPolicy {
        enabledPlugins.reduce(.none) { $0.merging($1.launchPolicy(for: agent)) }
    }

    /// How `agent` applies policy: the translator of the plugin that provides it.
    func policyTranslator(for agent: AgentDefinition.ID) -> (any SessionPolicyTranslator)? {
        plugins.first { $0.plugin.manifest.agents.contains { $0.id == agent.rawValue } }?.plugin.policyTranslator
    }

    func permissionMapping(for agent: AgentDefinition.ID) -> TaskPermissionMapping {
        policyTranslator(for: agent)?.permissionMapping ?? .standard
    }

    /// The `_meta` for `session/new` and `session/load` that carries the session's policy.
    func sessionMeta(for session: SessionContext) -> [String: JSONValue] {
        policyTranslator(for: session.agent)?.sessionMeta(for: sessionPolicy(for: session)) ?? [:]
    }

    /// Environment `agent` launches with to carry the policy for all its sessions.
    func launchEnvironment(for agent: AgentDefinition.ID) -> [String: String] {
        policyTranslator(for: agent)?.launchEnvironment(for: launchPolicy(for: agent)) ?? [:]
    }

    /// Readers for enabled agents' past sessions, for search (docs/search.md).
    var historyReaders: [(agent: AgentDefinition.ID, reader: any SessionHistoryReader)] {
        enabledPlugins.flatMap { plugin in
            plugin.manifest.agents.compactMap { manifest in
                let agent = AgentDefinition.ID(rawValue: manifest.id)
                return plugin.historyReader(for: agent).map { (agent, $0) }
            }
        }
    }

    /// The first enabled plugin that can title sessions.
    var titler: (any SessionTitler)? {
        enabledPlugins.lazy.compactMap(\.titler).first
    }

    /// Returns once every enabled plugin has what agents' launches depend on, with the ids of those
    /// prepared. Admission is checked again before each plugin starts and after it finishes, so one
    /// the organization revokes meanwhile is neither prepared nor counted, and contributes nothing.
    @discardableResult
    func prepareForLaunch() async -> Set<String> {
        var prepared: Set<String> = []
        for plugin in enabledPlugins {
            let id = plugin.manifest.id
            guard isActive(id) else { continue }
            await plugin.prepareForLaunch()
            if isActive(id) { prepared.insert(id) }
        }
        return prepared
    }

    /// Delivers an event to each enabled plugin still admitted when its turn comes.
    func broadcast(_ event: SessionEvent) async {
        for plugin in enabledPlugins where isActive(plugin.manifest.id) {
            await plugin.handle(event)
        }
    }

    /// Whether the plugin is among the enabled ones under the policy as it is now.
    private func isActive(_ id: String) -> Bool {
        enabledPlugins.contains { $0.manifest.id == id }
    }

    // MARK: - Cached contributions

    /// What the lists above are worked out from changing: the loaded plugins, the user's choices,
    /// experiment values (only while a plugin uses them) or the organization's policy.
    private struct Contributions {
        let plugins: [LoadedPlugin]
        let enabledPlugins: [any NativePlugin]
        let agents: [AgentDefinition]
        let commandKnowledge: CommandKnowledge
    }

    /// Views, the agents and the idle loop read the lists many times over, and working them out
    /// copies every manifest, so they're kept until something they come from changes. Readers
    /// observe `revision`, which moves whenever the kept lists are dropped.
    private var revision = 0
    @ObservationIgnored private var cached: Contributions?
    /// From the moment an input is about to change until the change has landed. Observation reports
    /// a change before it happens, so lists worked out meanwhile may be stale and aren't kept.
    @ObservationIgnored private var isSettling = false

    private var contributions: Contributions {
        _ = revision
        if let cached { return cached }
        let fresh = withObservationTracking(makeContributions) { [weak self] in
            MainActor.assumeIsolated { self?.inputWillChange() }
        }
        if !isSettling { cached = fresh }
        return fresh
    }

    private func inputWillChange() {
        cached = nil
        revision &+= 1
        guard !isSettling else { return }
        isSettling = true
        Task { [weak self] in self?.isSettling = false }
    }

    private func makeContributions() -> Contributions {
        let plugins: [LoadedPlugin]
        if loadedPlugins.contains(where: \.usesExperiments) {
            let values = ExperimentStore.shared.current
            plugins = loadedPlugins.map { $0.applyingExperiments(values) }
        } else {
            plugins = loadedPlugins
        }
        let policy = policyCenter.policy
        let system = SystemPlugins.current(policy: policy).filter {
            policy.admission(ofPlugin: $0.manifest.id, origin: .system, capabilities: $0.capabilities).isAdmitted
        }
        let enabled = plugins.filter { isEnabled($0.id) }.map(\.plugin) + system
        let runsAgents = policy.decision(for: .agentExecution).isPermitted
        let agents = enabled.flatMap { plugin in
            let manifest = plugin.manifest
            return manifest.agents.filter { runsAgents && policy.agents.allows($0.id) }.map { agent in
                var agent = agent
                agent.env.merge(policy.agents.environment[agent.id] ?? [:]) { $1 }
                return AgentDefinition(agent, pluginID: manifest.id)
            }
        }
        var knowledge = CommandKnowledge.bundled.adding(policy.commandKnowledge, source: "Organization policy")
        for plugin in enabled {
            if let document = plugin.manifest.commandKnowledge, let data = try? JSONEncoder().encode(document) {
                knowledge = knowledge.adding(.load(data), source: "Plugin \(plugin.manifest.id)")
            }
        }
        return Contributions(plugins: plugins, enabledPlugins: enabled, agents: agents, commandKnowledge: knowledge)
    }

    // MARK: - Validation

    private struct InvalidManifest: LocalizedError {
        let errorDescription: String?
    }

    private func validate(_ manifest: PluginManifest, against loaded: [LoadedPlugin]) throws {
        if loaded.contains(where: { $0.id == manifest.id }) {
            throw InvalidManifest(errorDescription: "Another plugin already uses the id \"\(manifest.id)\".")
        }
        let agentIDs = Set(loaded.flatMap { $0.plugin.manifest.agents.map(\.id) })
        if let duplicate = manifest.agents.first(where: { agentIDs.contains($0.id) }) {
            throw InvalidManifest(
                errorDescription: "Another plugin already provides an agent with the id \"\(duplicate.id)\".")
        }
        if let server = manifest.mcpServers.first(where: { $0.server == nil }) {
            throw InvalidManifest(
                errorDescription: "MCP server \"\(server.name)\" needs exactly one of \"command\" or \"url\".")
        }
    }

    private static func describe(_ error: any Error) -> String {
        switch error {
        case DecodingError.keyNotFound(let key, _): "Missing \"\(key.stringValue)\"."
        case DecodingError.typeMismatch(_, let context), DecodingError.valueNotFound(_, let context):
            "Wrong type at \"\(context.codingPath.map(\.stringValue).joined(separator: "."))\"."
        case DecodingError.dataCorrupted: "The file isn't valid JSON."
        default: error.localizedDescription
        }
    }
}

/// A plugin that is only a manifest: it contributes data and no behavior.
struct ManifestPlugin: NativePlugin {
    let manifest: PluginManifest
    /// Built-in agents' own way of applying session policy; manifests from disk have none.
    var policyTranslator: (any SessionPolicyTranslator)?
    /// Built-in agents' reader for their past sessions (docs/search.md); manifests from disk have none.
    var historyReader: (any SessionHistoryReader)?

    init(
        manifest: PluginManifest, policyTranslator: (any SessionPolicyTranslator)? = nil,
        historyReader: (any SessionHistoryReader)? = nil
    ) {
        self.manifest = manifest
        self.policyTranslator = policyTranslator
        self.historyReader = historyReader
    }

    func historyReader(for agent: AgentDefinition.ID) -> (any SessionHistoryReader)? {
        manifest.agents.contains { $0.id == agent.rawValue } ? historyReader : nil
    }

    var capabilities: Set<PolicyCapability>? {
        manifest.capabilities.union(historyReader == nil ? [] : [.search])
    }
}
