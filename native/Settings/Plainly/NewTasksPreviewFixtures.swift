#if DEBUG
import ACP
import Foundation
import TaskDefaults

enum NewTasksPreviewFixtures {
    static var requested: String? { UserDefaults.standard.string(forKey: "newTasksFixture") }
    private static var stores: [String: UserDefaults] = [:]

    static func model(
        agent: AgentDefinition.ID = .init(rawValue: "codex"), name: String = "Codex", project: Project? = nil,
        state: String = "populated"
    ) -> NewTasksDefaultsModel {
        let key = "\(agent.rawValue)/\(project?.id.uuidString ?? "all")/\(state)"
        let defaults = stores[key] ?? PreviewUserDefaults()
        if stores[key] == nil, state != "empty" {
            for (setting, values, initial) in [
                (
                    AgentSessionDefaults.Setting.model, [("gpt-6.1-sol", "gpt-6.1-sol"), ("gpt-6-luna", "gpt-6-luna")],
                    "gpt-6.1-sol"
                ),
                (.effort, [("low", "Low"), ("high", "High")], "low"),
            ] {
                let cache = values.map { ["value": $0.0, "name": $0.1] }
                defaults.set(
                    try? JSONSerialization.data(withJSONObject: cache), forKey: setting.key(for: agent) + ".offered")
                defaults.set(initial, forKey: setting.key(for: agent) + ".agentDefault")
                defaults.set(setting.category, forKey: setting.key(for: agent) + ".option")
            }
            defaults.set("high", forKey: AgentSessionDefaults.Setting.effort.key(for: agent))
            if state == "managed" {
                defaults.set("auto", forKey: TaskPermissionDefaults.key)
            }
            if state == "unavailable" {
                defaults.set("retired-model", forKey: AgentSessionDefaults.Setting.model.key(for: agent))
            }
            if let project {
                defaults.set("gpt-6.1-sol", forKey: ProjectTaskDefaults.modelKey(for: project.id, agent: agent))
            }
        }
        stores[key] = defaults
        return NewTasksDefaultsModel(agent: agent, agentName: name, project: project, defaults: defaults)
    }

    static func receipt(managed: Bool) -> NewTasksSettingReceipt {
        NewTasksSettingReceipt(
            title: "Permissions", context: "for Claude Code in native", value: "Edit files",
            source: managed ? .organization("Northwind Federal IT") : .project("native"),
            layers: [
                .init(
                    name: "Northwind Federal IT", symbol: "building.2", value: managed ? "Up to Edit files" : nil,
                    wins: managed, isOrganization: true),
                .init(name: "native", symbol: "folder", value: managed ? nil : "Edit files", wins: !managed),
                .init(name: "You", symbol: "person", value: "Auto", overridden: true),
                .init(name: "Claude Code", symbol: "terminal", value: "Ask before edits"),
            ], note: "The project's choice comes first.",
            help: managed ? "Northwind Federal IT decides this. Ask in #it-help." : nil,
            reason: managed ? "the most allowed" : nil)
    }

    static let budget = TaskContextBudget(
        parts: [
            .init(.tools, tokens: 14600), .init(.instructions, tokens: 2100), .init(.skills, tokens: 1200),
        ], window: 200000)

    /// Load rows for `agent`, so its own items carry its name. A project's own rows appear only
    /// when that project is selected, named for it.
    static func items(
        agent: String = "Codex", project: String? = nil, organization: String? = nil
    ) -> [NewTasksLoadItem] {
        // Claude Code reads CLAUDE.md; the other built-in agents read AGENTS.md.
        let file = agent == "Claude Code" ? "CLAUDE.md" : "AGENTS.md"
        let shared: [NewTasksLoadItem] = [
            .init(id: "agent-instructions", name: file, source: "\(agent)'s own", kind: .instructions, tokens: 600),
            .init(
                id: "github", name: "github", source: "Shared with every agent", kind: .tools, tokens: 9100,
                control: .switchable(true)),
            .init(
                id: "linear", name: "linear", source: "\(agent)'s own", kind: .tools, tokens: nil,
                detail: "Couldn't connect at the last check. \(agent) may sign in itself.", needsAttention: true),
            .init(
                id: "release-notes", name: "release-notes", source: "Yours", kind: .skills, tokens: 100,
                control: .switchable(true)),
        ]
        // Only a managed Mac has servers its organization requires.
        let required: [NewTasksLoadItem] =
            organization.map {
                [
                    .init(
                        id: "northwind-docs", name: "northwind-docs", source: $0, kind: .tools, tokens: 2100,
                        control: .required)
                ]
            } ?? []
        guard let project else { return shared + required }
        return [
            .init(
                id: "project-instructions", name: file, source: project, kind: .instructions, tokens: 1400,
                loadedBy: agent),
            .init(
                id: "playwright", name: "playwright", source: project, kind: .tools, tokens: 4600,
                control: .switchable(true)),
            .init(
                id: "sentry", name: "sentry", source: project, kind: .tools, tokens: 2400, included: false,
                control: .switchable(false)),
        ] + shared + required
    }
}
#endif
