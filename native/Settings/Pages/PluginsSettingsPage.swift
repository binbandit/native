import AppKit
import SwiftUI

extension SettingsPane.ID {
    static let plugins = Self("plugins")
}

extension SettingsPane {
    static func plugins(registry: PluginRegistry) -> SettingsPane {
        SettingsPane(
            id: .plugins,
            title: "Plugins",
            systemImage: "puzzlepiece.extension",
            group: .agents,
            order: 10,
            keywords: ["mcp", "reload", "folder", "plugin.json"],
            searchEntries: {
                registry.plugins.map { loaded in
                    let manifest = loaded.plugin.manifest
                    return SettingsSearchEntry(id: PluginsSettingsPage.rowID(manifest.id), title: manifest.name, description: manifest.description ?? "", keywords: [manifest.id])
                }
            },
            content: { PluginsSettingsPage() }
        )
    }
}

struct PluginsSettingsPage: View {
    @Environment(PluginRegistry.self) private var registry

    static func rowID(_ pluginID: String) -> SettingsRowID {
        SettingsRowID("plugin.\(pluginID)")
    }

    var body: some View {
        SettingsPage {
            SettingsHeader(
                title: "Plugins",
                description: Text("Changes apply to sessions started afterwards. Agents start or stop right away.")
            ) {
                Button("Reload", systemImage: "arrow.clockwise") { registry.reload() }
                    .buttonStyle(.ds(.secondary, size: .medium))
                Button("Open Plugins Folder", systemImage: "folder", action: openFolder)
                    .buttonStyle(.ds(.secondary, size: .medium))
            }
            SettingsRowGroup {
                ForEach(registry.plugins) { loaded in
                    PluginRow(loaded: loaded, isEnabled: Binding(
                        get: { registry.isEnabled(loaded.id) },
                        set: { registry.setEnabled($0, for: loaded.id) }
                    ))
                }
            }
            if !registry.failures.isEmpty {
                VStack(alignment: .leading, spacing: DS.Space.md) {
                    SettingsSubheading("Couldn't load")
                    SettingsRowGroup {
                        ForEach(registry.failures) { failure in
                            SettingsRow(
                                failure.url.deletingLastPathComponent().lastPathComponent,
                                description: Text(failure.message).foregroundStyle(.dsDanger),
                                detail: Text(abbreviated(failure.url)).font(SettingsTextStyle.mono.font)
                            ) { EmptyView() }
                        }
                    }
                }
            }
            Text("Add a plugin by creating \(Text(verbatim: "~/.native/plugins/<id>/plugin.json").font(SettingsTextStyle.mono.font)). Manifests can contribute agents that speak ACP and MCP servers for every session.")
                .settingsText(.body)
                .foregroundStyle(.dsTextSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func openFolder() {
        let folder = PluginRegistry.directory
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        NSWorkspace.shared.open(folder)
    }

    private func abbreviated(_ url: URL) -> String {
        (url.path(percentEncoded: false) as NSString).abbreviatingWithTildeInPath
    }
}

private struct PluginRow: View {
    let loaded: PluginRegistry.LoadedPlugin
    @Binding var isEnabled: Bool

    private var manifest: PluginManifest { loaded.plugin.manifest }

    var body: some View {
        SettingsRow(
            id: PluginsSettingsPage.rowID(manifest.id),
            title: Text(manifest.name),
            description: manifest.description.map(Text.init),
            detail: contributions.isEmpty ? nil : Text(contributions.joined(separator: " · "))
        ) {
            if let version = manifest.version {
                Text(version)
                    .settingsText(.caption)
                    .foregroundStyle(.dsTextSecondary)
            }
            if case .builtIn = loaded.source {
                SettingsBadge("Built-in")
            }
        } control: {
            SettingsSwitch(manifest.name, isOn: $isEnabled)
        }
    }

    private var contributions: [String] {
        var parts: [String] = []
        if !manifest.agents.isEmpty {
            parts.append("Agents: " + manifest.agents.map(\.name).joined(separator: ", "))
        }
        if !manifest.mcpServers.isEmpty {
            parts.append("MCP: " + manifest.mcpServers.map(\.name).joined(separator: ", "))
        }
        if loaded.plugin.titler != nil {
            parts.append("Names sessions")
        }
        if case .manifest(let url) = loaded.source {
            parts.append((url.deletingLastPathComponent().path(percentEncoded: false) as NSString).abbreviatingWithTildeInPath)
        }
        return parts
    }
}
