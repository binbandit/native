import ACP
import Foundation

/// The agent and model a project's new tasks start with when the user picks no other:
/// `projectDefaults.<project id>.agent`, and a model per agent (`.<agent id>.model`), in the user
/// defaults. Every task the project starts with that agent gets its model: ones the user starts,
/// pull requests opened as tasks, workflow steps and expeditions. Without them, a task starts with
/// the agent used last and that agent's own defaults (`AgentSessionDefaults`).
enum ProjectTaskDefaults {
    static func setAgent(
        _ agent: AgentDefinition.ID?, for project: Project.ID, defaults: UserDefaults = .standard,
        undoManager: UndoManager? = nil
    ) {
        let previous = self.agent(for: project, defaults: defaults)
        guard previous != agent else { return }
        defaults.set(agent?.rawValue, forKey: agentKey(for: project))
        undoManager?.registerUndo(withTarget: defaults) { defaults in
            MainActor.assumeIsolated {
                setAgent(previous, for: project, defaults: defaults, undoManager: undoManager)
            }
        }
        undoManager?.setActionName("Change Starting Agent")
    }

    static func agentKey(for project: Project.ID) -> String {
        "projectDefaults.\(project.uuidString).agent"
    }

    /// Per agent, so the model stays put when the project's agent changes, and one can be set for
    /// whichever agent was used last.
    static func modelKey(for project: Project.ID, agent: AgentDefinition.ID) -> String {
        "projectDefaults.\(project.uuidString).\(agent.rawValue).model"
    }

    static func agent(for project: Project.ID, defaults: UserDefaults = .standard) -> AgentDefinition.ID? {
        defaults.string(forKey: agentKey(for: project)).map(AgentDefinition.ID.init(rawValue:))
    }

    /// The model the project's new tasks with `agent` start on.
    static func model(
        for project: Project.ID, agent: AgentDefinition.ID, defaults: UserDefaults = .standard
    ) -> String? {
        defaults.string(forKey: modelKey(for: project, agent: agent))
    }
    static func key(for project: Project.ID, agent: AgentDefinition.ID, setting: AgentSessionDefaults.Setting) -> String
    {
        "projectDefaults.\(project.uuidString).\(agent.rawValue).\(setting.rawValue)"
    }

    static func value(
        for project: Project.ID, agent: AgentDefinition.ID, setting: AgentSessionDefaults.Setting,
        defaults: UserDefaults = .standard
    ) -> String? {
        defaults.string(forKey: key(for: project, agent: agent, setting: setting)).flatMap { $0.isEmpty ? nil : $0 }
    }

}
