import ACP
import Foundation

extension HostAgent {
    /// Uses this running instance's negotiation and this session's current settings. Cached model
    /// catalogs cannot establish resume compatibility or the permissions of a live task.
    public func effectiveCapabilities(options: [ConfigOption] = []) -> EffectiveAgentCapabilities {
        let response = initialize.flatMap { value in
            (try? JSONEncoder().encode(value)).flatMap { try? JSONDecoder().decode(InitializeResponse.self, from: $0) }
        }
        return EffectiveAgentCapabilities(
            negotiated: state == .ready ? response?.agentCapabilities : nil,
            options: options, steeringPolicy: state == .ready ? launchedSpec?.steeringPolicy : nil)
    }
}
