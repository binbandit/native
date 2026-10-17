import Foundation
import Observation

/// Which agents are installed, checked against the user's login-shell PATH when agents sync and
/// again whenever the user says they've installed one, so a new CLI shows up without a relaunch.
@Observable
final class AgentInstallations {
    private var checks: [AgentDefinition.ID: AgentInstallation] = [:]
    /// When the agents were last checked; nil before the first check.
    private(set) var checkedAt: Date?

    /// Checks every agent against `environment`, replacing what was known.
    func check(_ agents: [AgentDefinition], environment: [String: String]) {
        checks = Dictionary(agents.map { ($0.id, AgentInstallation($0.manifest, environment: environment)) }) { $1 }
        checkedAt = .now
    }

    /// Nil until the agent has been checked; agents are assumed installed until then.
    subscript(agent: AgentDefinition.ID) -> AgentInstallation? {
        checks[agent]
    }

    func isInstalled(_ agent: AgentDefinition.ID) -> Bool {
        checks[agent]?.isInstalled ?? true
    }

    /// The agents of `agents` that aren't installed, in their order: what Add Agent offers.
    func notInstalled(_ agents: [AgentDefinition]) -> [AgentDefinition] {
        agents.filter { !isInstalled($0.id) }
    }
}
