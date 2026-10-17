import ACP
import Foundation
import Observation
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

        var id: String { plugin.manifest.id }
    }

    struct LoadFailure: Identifiable, Hashable {
        let url: URL
        let message: String

        var id: URL { url }
    }

    /// `~/.native/plugins`, unless the `pluginsDirectory` default names another folder: launch with
    /// `-pluginsDirectory <path>` to try plugins without touching the user's own.
    static let directory = UserDefaults.standard.string(forKey: "pluginsDirectory").map { URL(filePath: $0, directoryHint: .isDirectory) }
        ?? FileManager.default.homeDirectoryForCurrentUser.appending(path: ".native/plugins", directoryHint: .isDirectory)

    private(set) var plugins: [LoadedPlugin] = []
    private(set) var failures: [LoadFailure] = []
    /// The user's explicit on/off choices; a plugin without one follows `isEnabledByDefault`.
    private var choices: [String: Bool]

    private let builtIns: [any NativePlugin]
    private let logger = Logger(subsystem: "Native", category: "Plugins")
    private static let choicesKey = "pluginChoices"
    /// Before plugins had defaults, only turning one off was recorded.
    private static let legacyDisabledKey = "disabledPlugins"

    init(builtIns: [any NativePlugin] = BuiltInPlugins.all) {
        self.builtIns = builtIns
        let defaults = UserDefaults.standard
        if let stored = defaults.dictionary(forKey: Self.choicesKey) as? [String: Bool] {
            choices = stored
        } else {
            let disabled = defaults.stringArray(forKey: Self.legacyDisabledKey) ?? []
            choices = Dictionary(uniqueKeysWithValues: disabled.map { ($0, false) })
        }
        reload()
    }

    /// Reads the plugins folder again. Built-ins come first, so their ids can't be taken over.
    func reload() {
        var loaded = builtIns.map { LoadedPlugin(plugin: $0, source: .builtIn) }
        var failures: [LoadFailure] = []
        let folders = (try? FileManager.default.contentsOfDirectory(at: Self.directory, includingPropertiesForKeys: nil, options: .skipsHiddenFiles)) ?? []
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
        plugins = loaded
        self.failures = failures
    }

    func isEnabled(_ id: String) -> Bool {
        choices[id] ?? plugins.first { $0.id == id }?.plugin.isEnabledByDefault ?? true
    }

    /// Records the user's choice, which then outlasts any change to the plugin's default.
    func setEnabled(_ enabled: Bool, for id: String) {
        choices[id] = enabled
        UserDefaults.standard.set(choices, forKey: Self.choicesKey)
    }

    // MARK: - Contributions of enabled plugins

    var enabledPlugins: [any NativePlugin] {
        plugins.filter { isEnabled($0.id) }.map(\.plugin)
    }

    var agents: [AgentDefinition] {
        enabledPlugins.flatMap { plugin in
            plugin.manifest.agents.map { AgentDefinition($0, pluginID: plugin.manifest.id) }
        }
    }

    func agent(_ id: AgentDefinition.ID) -> AgentDefinition? {
        agents.first { $0.id == id }
    }

    /// Every MCP server enabled plugins want the agent to have for this session.
    func mcpServers(for session: SessionContext) -> [MCPServer] {
        enabledPlugins.flatMap { plugin in
            plugin.manifest.mcpServers.compactMap(\.server) + plugin.mcpServers(for: session)
        }
    }

    /// The first enabled plugin that can title sessions.
    var titler: (any SessionTitler)? {
        enabledPlugins.lazy.compactMap(\.titler).first
    }

    func broadcast(_ event: SessionEvent) async {
        for plugin in enabledPlugins {
            await plugin.handle(event)
        }
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
            throw InvalidManifest(errorDescription: "Another plugin already provides an agent with the id \"\(duplicate.id)\".")
        }
        if let server = manifest.mcpServers.first(where: { $0.server == nil }) {
            throw InvalidManifest(errorDescription: "MCP server \"\(server.name)\" needs exactly one of \"command\" or \"url\".")
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
}
