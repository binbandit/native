import ACP
import Foundation

/// The agent and model a project's new tasks start with when the user picks no other:
/// `projectDefaults.<project id>.agent` and `.model` in the user defaults. The model is one of that
/// agent's, so it applies to the project's tasks with that agent, picked or not. Without them, a
/// task starts with the agent used last and that agent's own defaults (`AgentSessionDefaults`).
enum ProjectTaskDefaults {
    static func agentKey(for project: Project.ID) -> String {
        "projectDefaults.\(project.uuidString).agent"
    }

    static func modelKey(for project: Project.ID) -> String {
        "projectDefaults.\(project.uuidString).model"
    }

    static func agent(for project: Project.ID, defaults: UserDefaults = .standard) -> AgentDefinition.ID? {
        defaults.string(forKey: agentKey(for: project)).map(AgentDefinition.ID.init(rawValue:))
    }

    static func model(for project: Project.ID, defaults: UserDefaults = .standard) -> String? {
        defaults.string(forKey: modelKey(for: project))
    }

    /// Sets the project's agent; a different agent forgets the model, which was the old agent's.
    static func setAgent(_ agent: AgentDefinition.ID?, for project: Project.ID, defaults: UserDefaults = .standard) {
        guard agent != self.agent(for: project, defaults: defaults) else { return }
        defaults.set(agent?.rawValue, forKey: agentKey(for: project))
        defaults.removeObject(forKey: modelKey(for: project))
    }

    static func setModel(_ model: String?, for project: Project.ID, defaults: UserDefaults = .standard) {
        defaults.set(model, forKey: modelKey(for: project))
    }

    /// What a new task in the project with `agent` starts with, over the agent's own defaults.
    static func sessionSettings(
        for project: Project.ID, agent: AgentDefinition.ID, defaults: UserDefaults = .standard
    ) -> [AgentSessionDefaults.Setting: String] {
        guard self.agent(for: project, defaults: defaults) == agent,
            let model = model(for: project, defaults: defaults)
        else { return [:] }
        return [.model: model]
    }
}
