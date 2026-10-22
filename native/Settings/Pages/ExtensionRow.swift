import CodeThemes
import SwiftUI

/// One plugin on the Extensions page: what it adds, what switching it off does, and where it
/// comes from.
struct ExtensionRow: View {
    let loaded: PluginRegistry.LoadedPlugin
    @Binding var isEnabled: Bool

    private var manifest: PluginManifest { loaded.plugin.manifest }

    var body: some View {
        SettingsRow(
            id: ExtensionsSettingsPage.rowID(manifest.id),
            title: Text(manifest.name),
            description: manifest.description.map(Text.init),
            detail: Text(detailLines.joined(separator: "\n"))
        ) {
            if let version = manifest.version {
                Text(version)
                    .settingsText(.caption)
                    .foregroundStyle(.dsTextTertiary)
            }
            if loaded.source == .builtIn {
                SettingsBadge("Built-in")
            }
        } control: {
            SettingsSwitch(manifest.name, isOn: $isEnabled)
        }
    }

    private var detailLines: [String] {
        var lines = [consequence]
        if !contributions.isEmpty {
            lines.append(contributions.joined(separator: " · "))
        }
        // A theme that fails its checks is left out; say which and why, so its author can fix it.
        lines += PluginThemeCatalog.check(manifest).problems.map { "Theme “\($0.theme)” isn’t used: \($0.reason)." }
        if case .manifest(let url) = loaded.source {
            lines.append(Self.displayPath(url.deletingLastPathComponent()))
        }
        return lines
    }

    /// What turning the plugin off takes away, in the user's terms.
    private var consequence: String {
        var effects: [String] = []
        if !manifest.agents.isEmpty {
            let names = ListFormatter.localizedString(byJoining: manifest.agents.map(\.name))
            effects.append(
                "\(names) \(manifest.agents.count == 1 ? "stops and isn't" : "stop and aren't") offered for new tasks")
        }
        if !manifest.mcpServers.isEmpty {
            effects.append("new tasks don't get its MCP \(manifest.mcpServers.count == 1 ? "server" : "servers")")
        }
        if !manifest.workflows.isEmpty {
            effects.append("its workflows aren't offered")
        }
        if !manifest.themes.isEmpty {
            effects.append("its themes go back to the defaults")
        }
        if loaded.plugin.titler != nil {
            effects.append("tasks keep the titles their agents give them")
        }
        guard !effects.isEmpty else { return "When off, \(manifest.name) doesn't run." }
        return "When off, " + ListFormatter.localizedString(byJoining: effects) + "."
    }

    private var contributions: [String] {
        var parts: [String] = []
        if !manifest.agents.isEmpty {
            parts.append("Agents: " + manifest.agents.map(\.name).joined(separator: ", "))
        }
        if !manifest.mcpServers.isEmpty {
            parts.append("MCP: " + manifest.mcpServers.map(\.name).joined(separator: ", "))
        }
        if !manifest.workflows.isEmpty {
            parts.append("Workflows: \(manifest.workflows.count)")
        }
        let themes = PluginThemeCatalog.check(manifest)
        let themeNames = themes.codeThemes.map(\.name) + themes.accents.map(\.name)
        if !themeNames.isEmpty {
            parts.append("Themes: " + themeNames.joined(separator: ", "))
        }
        return parts
    }

    static func displayPath(_ url: URL) -> String {
        (url.path(percentEncoded: false) as NSString).abbreviatingWithTildeInPath
    }
}

#if DEBUG
#Preview("Extension rows") {
    let registry = SettingsPreviewFixtures.registry()
    DSPreviewPair {
        SettingsRowGroup {
            ForEach(registry.plugins.prefix(4), id: \.id) { loaded in
                ExtensionRow(loaded: loaded, isEnabled: .constant(loaded.id != "cursor"))
            }
        }
        .settingsPreviewPage()
    }
}
#endif
