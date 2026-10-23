import SwiftUI

extension SettingsPane.ID {
    static let extensions = Self("extensions")
}

extension SettingsPane {
    static func extensions(registry: PluginRegistry) -> SettingsPane {
        SettingsPane(
            id: .extensions,
            title: "Extensions",
            systemImage: "puzzlepiece.extension",
            group: .extensions,
            order: 0,
            keywords: ["plugins", "plugin.json", "reload", "folder", "minimal"],
            searchEntries: {
                registry.plugins.map { loaded in
                    let manifest = loaded.plugin.manifest
                    return SettingsSearchEntry(
                        id: ExtensionsSettingsPage.rowID(manifest.id), title: manifest.name,
                        description: manifest.description ?? "", keywords: [manifest.id])
                }
            },
            content: { ExtensionsSettingsPage(registry: registry) }
        )
    }
}

/// Every plugin, built in or installed, with a switch. This is where the user turns on what Native
/// adds beyond the agents: Native starts minimal, so some built-ins start off.
struct ExtensionsSettingsPage: View {
    let registry: PluginRegistry
    @Environment(\.settingsPlainly) private var plainly

    #if os(macOS)
    @Environment(\.openURL) private var openURL
    #endif

    static func rowID(_ pluginID: String) -> SettingsRowID {
        SettingsRowID("plugin.\(pluginID)")
    }

    private var builtIn: [PluginRegistry.LoadedPlugin] {
        registry.plugins.filter { $0.source == .builtIn && (!plainly || $0.plugin.manifest.agents.isEmpty) }
    }

    private var installed: [PluginRegistry.LoadedPlugin] {
        registry.plugins.filter { $0.source != .builtIn }
    }

    var body: some View {
        SettingsPage {
            SettingsHeader(
                title: "Extensions",
                description: Text(
                    "Turn on what you use. Changes apply to tasks started afterwards; agents start or stop right away."
                ),
                plainly: .init(
                    title: "Features",
                    description: "Native starts small. Turn on what you use; a feature that's off is gone, not hidden.")
            ) {
                Button("Reload", systemImage: "arrow.clockwise") { registry.reload() }
                    .buttonStyle(.ds(.secondary, size: .medium))
                    .help("Read the plugins folder again")
                #if os(macOS)
                Button("Open Plugins Folder", systemImage: "folder", action: openFolder)
                    .buttonStyle(.ds(.secondary, size: .medium))
                #endif
            }
            SettingsRowGroup {
                ForEach(builtIn) { loaded in
                    ExtensionRow(loaded: loaded, isEnabled: binding(for: loaded))
                }
            }
            VStack(alignment: .leading, spacing: DS.Space.lg) {
                SettingsSubheading(
                    "Your plugins", note: "Plugins in ~/.native/plugins, each a folder with a plugin.json.")
                if installed.isEmpty {
                    installedEmptyState
                } else {
                    SettingsRowGroup {
                        ForEach(installed) { loaded in
                            ExtensionRow(loaded: loaded, isEnabled: binding(for: loaded))
                                .settingsLocked(registry.isAllowed(loaded.id) ? nil : AgentsSettingsPage.notAllowed)
                        }
                    }
                }
            }
            if !registry.failures.isEmpty {
                VStack(alignment: .leading, spacing: DS.Space.lg) {
                    SettingsSubheading("Couldn't load", note: "Fix the file, then Reload.")
                    ForEach(registry.failures) { failure in
                        NoticeBanner(
                            tone: .danger,
                            title: "\(failure.url.deletingLastPathComponent().lastPathComponent) couldn't load",
                            detail: failure.message,
                            footnote: ExtensionRow.displayPath(failure.url)
                        ) {
                            Button("Reload") { registry.reload() }
                                .buttonStyle(.ds(.secondary))
                        }
                    }
                }
            }
        }
    }

    private var installedEmptyState: some View {
        SettingsNote("No plugins yet", systemImage: "shippingbox") {
            Text(
                "Add a folder with a plugin.json to ~/.native/plugins, then Reload. A plugin can add agents that speak ACP, MCP servers for every task, and workflows."
            )
        }
    }

    private func binding(for loaded: PluginRegistry.LoadedPlugin) -> Binding<Bool> {
        Binding(
            get: { registry.isEnabled(loaded.id) },
            set: { registry.setEnabled($0, for: loaded.id) }
        )
    }

    #if os(macOS)
    private func openFolder() {
        let folder = PluginRegistry.directory
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        openURL(folder)
    }
    #endif
}

#if DEBUG
#Preview("Extensions settings") {
    DSPreviewPair {
        ExtensionsSettingsPage(registry: SettingsPreviewFixtures.registry())
            .settingsPreviewPage()
    }
}
#endif
