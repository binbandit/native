import ACP
import SwiftUI

/// What the user set up that takes context, the most expensive kind first: MCP servers (with their
/// tools), memory files, skills and custom agents. These are the parts the user can trim.
struct ContextContributors: View {
    let report: ContextReport

    @State private var showsAllSkills = false

    private static let skillPreviewCount = 5

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.lg) {
            ForEach(sections) { section in
                VStack(alignment: .leading, spacing: 0) {
                    ContributorSectionHeader(title: section.title, tokens: TokenFormat.compact(total(of: section)))
                    rows(for: section)
                }
            }
        }
    }

    @ViewBuilder
    private func rows(for section: Section) -> some View {
        switch section {
        case .mcpServers(let servers):
            ForEach(servers) { server in
                MCPServerRow(server: server, tokens: report.tokens(of: server))
            }
        case .memoryFiles(let files):
            ForEach(files, id: \.path) { file in
                ContributorRow(title: URL(filePath: file.path).lastPathComponent, detail: file.type, tokens: TokenFormat.compact(file.tokens))
                    .help(file.path)
            }
        case .skills(let skills):
            let shown = showsAllSkills ? skills : Array(skills.prefix(Self.skillPreviewCount))
            ForEach(shown, id: \.name) { skill in
                ContributorRow(title: skill.name, detail: skill.source, tokens: TokenFormat.compact(skill.tokens))
            }
            if !showsAllSkills, skills.count > Self.skillPreviewCount {
                ShowAllButton(title: "Show all \(skills.count) skills") {
                    showsAllSkills = true
                }
            }
        case .agents(let agents):
            ForEach(agents, id: \.type) { agent in
                ContributorRow(title: agent.type, detail: agent.source, tokens: TokenFormat.compact(agent.tokens))
            }
        }
    }

    private var sections: [Section] {
        let skills = report.skills.sorted { ($0.tokens.value, $1.name) > ($1.tokens.value, $0.name) }
        let candidates: [Section] = [
            .mcpServers(report.mcpServers),
            .memoryFiles(report.memoryFiles.sorted { $0.tokens > $1.tokens }),
            .skills(skills),
            .agents(report.agents.sorted { $0.tokens > $1.tokens }),
        ]
        return candidates.filter { $0.tokens > 0 }.sorted { total(of: $0) > total(of: $1) }
    }

    /// The agent's own category total where it has one; items' counts are rounded.
    private func total(of section: Section) -> Int {
        report.categoryTokens(section.category) ?? section.tokens
    }

    private enum Section: Identifiable {
        case mcpServers([ContextReport.MCPServer])
        case memoryFiles([ContextReport.MemoryFile])
        case skills([ContextReport.Skill])
        case agents([ContextReport.CustomAgent])

        var id: String { title }

        var title: String {
            switch self {
            case .mcpServers: "MCP servers"
            case .memoryFiles: "Memory files"
            case .skills(let skills): "Skills · \(skills.count)"
            case .agents: "Custom agents"
            }
        }

        var category: String {
            switch self {
            case .mcpServers: "MCP tools"
            case .memoryFiles: "Memory files"
            case .skills: "Skills"
            case .agents: "Custom agents"
            }
        }

        var tokens: Int {
            switch self {
            case .mcpServers(let servers): servers.reduce(0) { $0 + $1.tokens }
            case .memoryFiles(let files): files.reduce(0) { $0 + $1.tokens }
            case .skills(let skills): skills.reduce(0) { $0 + $1.tokens.value }
            case .agents(let agents): agents.reduce(0) { $0 + $1.tokens }
            }
        }
    }
}
