import MCPClient
import SwiftUI

#if canImport(Skills)
import Skills
#endif

/// A project's MCP servers and skills: how many are on here and how many it switches for itself,
/// with a way to its own switches on their pages. The switches stay where they're kept
/// (`MCPLibrary`, `SkillLibrary`), so a page and this summary never disagree.
struct ProjectToolsSection: View {
    let project: Project

    @Environment(PluginRegistry.self) private var registry
    @Environment(SettingsPresentation.self) private var settings

    private var rows: ProjectSettingsRows { ProjectSettingsRows(project: project.id) }

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.lg) {
            SettingsSubheading(
                "MCP servers and skills",
                note:
                    "A switch set for \(project.name) wins over the one for every project. Agents pick changes up in their next session."
            )
            SettingsRowGroup {
                SettingsRow(id: rows.mcp, "MCP servers", description: Text(mcpSummary)) {
                    Button("Choose Servers…") { settings.open(.mcpServers, scopedTo: project.url) }
                }
                #if canImport(Skills)
                SettingsRow(id: rows.skills, "Skills", description: Text(skillsSummary)) {
                    Button("Choose Skills…") { settings.open(.skills, scopedTo: project.url) }
                }
                #endif
            }
        }
    }

    private var mcpSummary: String {
        guard let library = MCPServersPlugin.library(in: registry) else {
            return "The MCP Servers extension isn't loaded in this build."
        }
        guard registry.isEnabled(MCPServersPlugin.id) else {
            return "The MCP Servers extension is off, so agents only get the servers they load themselves."
        }
        let keys =
            library.servers.map(\.transport.endpoint.key)
            + library.agentServerGroups(in: project.url).map(\.endpoint.key)
        guard !keys.isEmpty else { return "No servers yet. Add one, and every agent gets it here." }
        let on = keys.filter { library.mode(of: $0, in: project.url) != .off }.count
        let here = keys.filter { library.switches.explicitMode(of: $0, in: project.url) != nil }.count
        return Self.summary(on: on, of: keys.count, noun: "server", switchedHere: here)
    }

    #if canImport(Skills)
    private var skillsSummary: String {
        guard let library = SkillsPlugin.library(in: registry) else {
            return "The Skills extension isn't loaded in this build."
        }
        guard registry.isEnabled(SkillsPlugin.id) else {
            return "The Skills extension is off, so switches don't reach agents."
        }
        // The project's own skills and everyone's, not other projects'.
        let keys =
            library.items.filter { item in
                item.places.contains { place in
                    place.root.scope.project.map { SkillPaths.key($0) == SkillPaths.key(project.url) } ?? true
                }
            }
            .map(\.key) + library.nativeSkills.map { SkillItem.key(for: $0.id) }
        guard !keys.isEmpty else { return "No skills yet. Install one, and the agents you choose load it here." }
        let on = keys.filter { library.mode(of: $0, in: project.url) == .on }.count
        let here = keys.filter { library.switches.explicitMode(of: $0, in: project.url) != nil }.count
        return Self.summary(on: on, of: keys.count, noun: "skill", switchedHere: here)
    }
    #endif

    /// "4 of 5 servers on here, 1 switched for this project only."
    private static func summary(on: Int, of total: Int, noun: String, switchedHere: Int) -> String {
        let count = total == 1 ? "1 \(noun)" : "\(on) of \(total) \(noun)s"
        let state = total == 1 ? (on == 1 ? "on" : "off") : "on"
        let here =
            switch switchedHere {
            case 0: "all following the switch for every project"
            case 1: "1 switched for this project only"
            default: "\(switchedHere) switched for this project only"
            }
        return "\(count) \(state) here, \(here)."
    }
}

#if NATIVE_PREVIEWS_WIP
#Preview("Project tools") {
    let app = AppModel.preview()
    DSPreviewPair {
        if let project = app.previewProject() {
            ProjectToolsSection(project: project)
                .settingsPreviewPage()
        }
    }
    .sidebarPreviewEnvironment(app)
    .environment(SettingsPreviewFixtures.registry())
}
#endif
