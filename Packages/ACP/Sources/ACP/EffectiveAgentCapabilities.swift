/// Effective support describes a negotiated mechanism, never proof that an agent obeyed it.
/// Authorization remains with Native's model and host policy at admission and execution.
public struct EffectiveAgentCapabilities: Sendable {
    public enum Feature: String, CaseIterable, Codable, Sendable {
        case model, options, permissions, resume, load, fork, steering, context, completion
    }

    public enum Support: String, Codable, Sendable { case supported, unsupported, unknown }
    public enum Enforcement: String, Codable, Sendable { case agent, native, both, none }
    public enum Reason: String, Codable, Sendable {
        case negotiated, notNegotiated, notAdvertised, reportedOptions, noOptions
        case pluginBoundary, nativeBoundary, notImplemented, turnEndOnly
    }

    public struct Capability: Equatable, Codable, Sendable {
        public let support: Support
        public let enforcement: Enforcement
        public let reason: Reason

        public var explanation: String {
            switch reason {
            case .negotiated: "The running agent advertised this mechanism."
            case .notNegotiated: "The running agent's capabilities have not been negotiated."
            case .notAdvertised: "The agent did not advertise this mechanism."
            case .reportedOptions:
                "The agent reports selectable settings; Native validates choices before applying them."
            case .noOptions: "This session has not reported a selectable setting for this feature."
            case .pluginBoundary: "The plugin declares delivery between tool steps, enforced by Native."
            case .nativeBoundary: "Native can carry selected history as labeled prompt context."
            case .notImplemented: "Native has no negotiated implementation of this operation."
            case .turnEndOnly: "An ACP turn end does not prove the task or its descendants finished."
            }
        }
    }

    public let negotiated: AgentCapabilities?
    public let options: [ConfigOption]
    public let steeringPolicy: SteeringPolicy?

    public init(
        negotiated: AgentCapabilities?, options: [ConfigOption] = [], steeringPolicy: SteeringPolicy? = nil
    ) {
        self.negotiated = negotiated
        self.options = options
        self.steeringPolicy = steeringPolicy
    }

    public subscript(feature: Feature) -> Capability {
        switch feature {
        case .model, .options, .permissions:
            let selections = options.filter { option in
                guard case .select(_, let choices) = option.kind, !choices.isEmpty else { return false }
                return feature == .options || option.category == (feature == .model ? "model" : "mode")
            }
            return Capability(
                support: selections.isEmpty ? .unknown : .supported,
                enforcement: selections.isEmpty ? .none : .both,
                reason: selections.isEmpty ? .noOptions : .reportedOptions)
        case .resume: return advertised(negotiated?.resumeSessions)
        case .load: return advertised(negotiated?.loadSession)
        case .fork:
            return Capability(support: .unsupported, enforcement: .none, reason: .notImplemented)
        case .steering:
            if negotiated?.steering == true {
                return Capability(
                    support: .supported, enforcement: steeringPolicy == .nonInterrupting ? .agent : .both,
                    reason: .negotiated)
            }
            if steeringPolicy == .afterTools {
                return Capability(support: .supported, enforcement: .native, reason: .pluginBoundary)
            }
            return advertised(negotiated.map { $0.steering })
        case .context:
            return Capability(support: .supported, enforcement: .native, reason: .nativeBoundary)
        case .completion:
            // An ACP stop reason ends a turn. It cannot prove the task or descendants finished.
            return Capability(support: .unsupported, enforcement: .none, reason: .turnEndOnly)
        }
    }

    private func advertised(_ value: Bool?) -> Capability {
        Capability(
            support: value.map { $0 ? .supported : .unsupported } ?? .unknown,
            enforcement: value == true ? .agent : .none,
            reason: value.map { $0 ? .negotiated : .notAdvertised } ?? .notNegotiated)
    }
}
