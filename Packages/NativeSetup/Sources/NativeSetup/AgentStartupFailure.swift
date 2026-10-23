/// The recovery state shared by Home and New Task when every installed, enabled agent failed.
/// Missing or disabled agents cannot recover this state, but a ready or starting agent can.
public struct AgentStartupFailure: Equatable, Sendable {
    public let agentNames: [String]

    public init?(agents: [(name: String, state: SetupReport.Agent.State)]) {
        let installed = agents.filter {
            switch $0.state {
            case .ready, .starting, .stopped: true
            case .notInstalled, .turnedOff, .notAllowed: false
            }
        }
        guard !installed.isEmpty, installed.allSatisfy({ $0.state == .stopped }) else { return nil }
        agentNames = installed.map(\.name)
    }

    public var title: String { "No agents could start" }

    public var message: String {
        "\(agentNames.joined(separator: ", ")) failed to start. Restart an agent, or check Settings > Agents."
    }
}
