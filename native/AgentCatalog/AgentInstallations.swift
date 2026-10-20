import Foundation
import Observation

/// Which agents are installed, checked against the user's login-shell PATH when agents sync and
/// again whenever the user says they've installed one, so a new CLI shows up without a relaunch.
@Observable
final class AgentInstallations {
    private var checks: [AgentDefinition.ID: AgentInstallation] = [:]
    /// When the agents were last checked; nil before the first check.
    private(set) var checkedAt: Date?
    /// What the previous launch's last check found installed, so those agents can have runtimes
    /// (and Home its cards) from the first frame rather than once this launch has checked.
    @ObservationIgnored private let installedLastLaunch: Set<AgentDefinition.ID>
    @ObservationIgnored private let defaults: UserDefaults

    private static let installedKey = "agents.installed"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        installedLastLaunch = Set(
            (defaults.stringArray(forKey: Self.installedKey) ?? []).map(AgentDefinition.ID.init(rawValue:)))
    }

    /// Checks every agent against `environment`, replacing what was known, and keeps the installed
    /// ones for the next launch.
    func check(_ agents: [AgentDefinition], environment: [String: String]) {
        checks = Dictionary(agents.map { ($0.id, AgentInstallation($0.manifest, environment: environment)) }) { $1 }
        checkedAt = .now
        let installed = agents.map(\.id).filter(isInstalled).map(\.rawValue)
        if defaults.stringArray(forKey: Self.installedKey) != installed {
            defaults.set(installed, forKey: Self.installedKey)
        }
    }

    /// Whether the previous launch's last check found `agent` installed.
    func wasInstalledLastLaunch(_ agent: AgentDefinition.ID) -> Bool {
        installedLastLaunch.contains(agent)
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
