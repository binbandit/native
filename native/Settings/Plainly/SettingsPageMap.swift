import Experiments
import SwiftUI

/// One map for navigation, search and the command palette. Original IDs remain valid deep links.
enum SettingsPageMap {
    static var isEnabled: Bool { isEnabled(in: .shared) }

    static func isEnabled(in store: ExperimentStore) -> Bool { store.value(of: .settingsPlainly) }

    static func destination(_ id: SettingsPane.ID) -> SettingsPane.ID {
        switch id {
        case .sounds: .notifications
        case .keepAwake, .pairedDevices, .hosts: .background
        case .gitHub, .scripts: .git
        case .celebrations: .appearance
        case .skills, .mcpServers: .toolsSkills
        case .modes: .newTasks
        default: id
        }
    }

    static func sectionID(_ id: SettingsPane.ID) -> SettingsRowID {
        SettingsRowID("settings.section.\(id.rawValue)")
    }

    static func panes(_ source: [SettingsPane], registry: PluginRegistry, plainly: Bool) -> [SettingsPane] {
        guard plainly else { return ordered(source) }
        let byID = Dictionary(uniqueKeysWithValues: source.map { ($0.id, $0) })
        func sections(_ ids: [SettingsPane.ID]) -> [SettingsPane] { ids.compactMap { byID[$0] } }
        func combined(
            _ id: SettingsPane.ID, title: String, icon: String, group: SettingsPane.Group, order: Int,
            parts: [SettingsPane.ID]
        ) -> SettingsPane {
            let pages = sections(parts)
            return SettingsPane(
                id: id, title: title, systemImage: icon, group: group, order: order,
                keywords: pages.flatMap { [$0.title] + $0.keywords },
                searchEntries: {
                    pages.flatMap { page in
                        let section = SettingsSearchEntry(
                            id: sectionID(page.id), title: sectionTitle(page.id, fallback: page.title))
                        return (page.id == id ? [] : [section]) + entries(page, registry: registry)
                    }
                }
            ) {
                SettingsCombinedPage(panes: pages, title: id == .toolsSkills ? title : nil)
            }
        }
        var result: [SettingsPane] = [
            combined(
                .general, title: "General", icon: "slider.horizontal.3", group: .personal, order: 0, parts: [.general]),
            combined(
                .appearance, title: "Appearance", icon: "paintpalette", group: .personal, order: 10,
                parts: [.appearance] + (registry.isEnabled(CelebrationsPlugin.id) ? [.celebrations] : [])),
            combined(
                .notifications, title: "Notifications", icon: "bell", group: .personal, order: 20,
                parts: [.notifications] + (registry.isEnabled(SoundsPlugin.id) ? [.sounds] : [])),
            combined(
                .keyboardShortcuts, title: "Keyboard", icon: "keyboard", group: .personal, order: 30,
                parts: [.keyboardShortcuts]),
            combined(.privacy, title: "Privacy", icon: "hand.raised", group: .personal, order: 40, parts: [.privacy]),
            .newTasks(registry: registry, modes: byID[.modes]),
            combined(.agents, title: "Agents", icon: "person.2", group: .tasks, order: 10, parts: [.agents]),
            combined(
                .background, title: "While You're Away", icon: "moon", group: .tasks, order: 20,
                parts: [.background, .keepAwake, .pairedDevices, .hosts]),
            combined(
                .aiInstructions, title: "Writing Style", icon: "pencil", group: .tasks, order: 40,
                parts: [.aiInstructions]),
            combined(
                .git, title: "Git", icon: "arrow.triangle.branch", group: .work, order: 0,
                parts: [.git, .gitHub, .scripts]),
            combined(.terminal, title: "Terminal", icon: "terminal", group: .work, order: 10, parts: [.terminal]),
            combined(.search, title: "Search", icon: "magnifyingglass", group: .work, order: 20, parts: [.search]),
            combined(.usage, title: "Usage", icon: "chart.bar", group: .work, order: 30, parts: [.usage]),
            combined(
                .extensions, title: "Features", icon: "puzzlepiece.extension", group: .native, order: 0,
                parts: [.extensions]),
            combined(
                .updates, title: "Updates", icon: "arrow.down.circle", group: .native, order: 20, parts: [.updates]),
        ]
        let tools = [
            registry.isEnabled(MCPServersPlugin.id) ? SettingsPane.ID.mcpServers : nil,
            registry.isEnabled(SkillsPlugin.id) ? .skills : nil,
        ].compactMap { $0 }.filter { byID[$0] != nil }
        result.removeAll { $0.id != .newTasks && byID[$0.id] == nil }
        if !tools.isEmpty {
            // Both libraries keep their own actions and scope; a shared scope is a later slice.
            result.append(
                combined(
                    .toolsSkills, title: "Tools & Skills", icon: "wrench.and.screwdriver",
                    group: .tasks, order: 30, parts: tools))
        }
        if byID[.labs] != nil {
            result.append(combined(.labs, title: "Labs", icon: "flask", group: .native, order: 10, parts: [.labs]))
        }
        let consumed = Set(
            result.map(\.id) + [
                .sounds, .keepAwake, .pairedDevices, .hosts, .gitHub, .scripts, .celebrations, .modes, .skills,
                .mcpServers,
            ])
        // Project and third-party pages retain their identity, icon and search targets.
        result += source.filter { !consumed.contains($0.id) }
        return ordered(result)
    }

    static func sectionTitle(_ id: SettingsPane.ID, fallback: String) -> String {
        switch id {
        case .background: "While You're Away"
        case .keepAwake: "Sleep"
        case .pairedDevices: "Your iPhone"
        case .hosts: "Other Macs"
        case .aiInstructions: "Writing Style"
        case .extensions: "Features"
        case .keyboardShortcuts: "Keyboard"
        default: fallback
        }
    }

    private static func entries(_ pane: SettingsPane, registry: PluginRegistry) -> [SettingsSearchEntry] {
        var entries = pane.searchEntries()
        if pane.id == .agents { entries.removeAll { $0.id.rawValue.hasSuffix(".defaults") } }
        if pane.id == .git { entries.removeAll { $0.id == GitSettingsPage.workspaceRow } }
        if pane.id == .notifications { entries.removeAll { $0.id == NotificationSettingsPage.dockBadgeRow } }
        if pane.id == .general { entries.append(GeneralSettingsPage.badgeEntry) }
        if pane.id == .extensions {
            let agentRows = Set(
                registry.plugins.filter { !$0.plugin.manifest.agents.isEmpty }
                    .map { ExtensionsSettingsPage.rowID($0.id) })
            entries.removeAll { agentRows.contains($0.id) }
        }
        return entries.map { entry in
            guard let copy = entry.plainly else { return entry }
            return SettingsSearchEntry(
                id: entry.id, title: copy.title,
                description: copy.description ?? "",
                keywords: entry.keywords + [entry.title])
        }
    }

    private static func ordered(_ panes: [SettingsPane]) -> [SettingsPane] {
        panes.sorted { ($0.group, $0.order, $0.id.rawValue) < ($1.group, $1.order, $1.id.rawValue) }
    }
}

extension SettingsPane.ID {
    static let newTasks = Self("new-tasks")
    static let toolsSkills = Self("tools-skills")
}
