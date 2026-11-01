/// An executable mechanism and an honest explanation of any substitution. Callers must still
/// confirm settings and recheck authorization after awaiting the agent.
public struct AgentTransitionPlan: Equatable, Codable, Sendable {
    public enum Outcome: String, Codable, Sendable { case exact, fallback, refused }
    public enum Action: String, Codable, Sendable {
        case reuse, setOptions, resume, loadWithReplay, createWithHandoff
        case steer, steerAfterTools, interruptAfterTools
    }
    public enum Reason: String, Codable, Sendable {
        case requested, freshConversation, incompatibleSession, resumeUnavailable, unsupportedFork
        case missingOption, unavailableValue, permissionEquivalent, stricterPermission, incomparablePermissions
        case noSafePermissions, toolBoundary, steeringUnavailable, unavailable, policyDenied, fallbackDisabled

        public var explanation: String {
            switch self {
            case .requested: "The target reports support for the requested operation."
            case .freshConversation: "This switch prepares a new conversation and carries local context."
            case .incompatibleSession:
                "Session identity is not shared with the target; local context must be transferred."
            case .resumeUnavailable: "Resume is not advertised; loading the session replays its history."
            case .unsupportedFork: "Native has no negotiated conversation fork mechanism."
            case .missingOption: "The target has not reported that setting."
            case .unavailableValue: "The requested value is not offered by the target."
            case .permissionEquivalent: "The existing permission translator found an equivalent control."
            case .stricterPermission: "The target offers a stricter permission control."
            case .incomparablePermissions: "The permission controls cannot be compared; review the selected fallback."
            case .noSafePermissions: "No allowed permission equivalent is available."
            case .toolBoundary: "Native waits for tools; this is not immediate non-interrupting steering."
            case .steeringUnavailable: "The target has not advertised steering or a plugin tool-boundary fallback."
            case .unavailable: "The target agent is unavailable."
            case .policyDenied: "Managed policy does not allow this transition."
            case .fallbackDisabled: "The requested operation is unavailable and fallback was disabled."
            }
        }
    }

    public let outcome: Outcome
    public let action: Action?
    public let reason: Reason
    public let values: [String: String]
    public var explanation: String { reason.explanation }

    public enum Request: Sendable {
        case reuse, freshConversation, resume, fork, steer
        case model(String)
        case options([String: String])
        case permissions(source: String?, forbidden: Set<String>)
    }

    /// `sameSession` is evidence supplied by the host, including runtime/account identity.
    /// An agent name or matching session id on another runtime is insufficient.
    public static func resolve(
        _ request: Request, target: EffectiveAgentCapabilities, sameSession: Bool = false,
        available: Bool = true, policyAllows: Bool = true, allowsFallback: Bool = true
    ) -> Self {
        func exact(_ action: Action, _ values: [String: String] = [:], reason: Reason = .requested) -> Self {
            Self(outcome: .exact, action: action, reason: reason, values: values)
        }
        func refused(_ reason: Reason) -> Self {
            Self(outcome: .refused, action: nil, reason: reason, values: [:])
        }
        func fallback(_ action: Action, _ reason: Reason, values: [String: String] = [:]) -> Self {
            allowsFallback
                ? Self(outcome: .fallback, action: action, reason: reason, values: values)
                : refused(.fallbackDisabled)
        }
        guard available else { return refused(.unavailable) }
        guard policyAllows else { return refused(.policyDenied) }
        switch request {
        case .freshConversation:
            return fallback(.createWithHandoff, .freshConversation)
        case .reuse:
            return sameSession ? exact(.reuse) : fallback(.createWithHandoff, .incompatibleSession)
        case .resume:
            guard sameSession else { return fallback(.createWithHandoff, .incompatibleSession) }
            if target[.resume].support == .supported { return exact(.resume) }
            if target[.load].support == .supported { return fallback(.loadWithReplay, .resumeUnavailable) }
            return fallback(.createWithHandoff, .freshConversation)
        case .fork:
            return refused(.unsupportedFork)
        case .model(let value):
            guard let option = target.options.first(where: { $0.category == "model" }) else {
                return refused(.missingOption)
            }
            return resolve(.options([option.id: value]), target: target)
        case .options(let values):
            for (id, value) in values {
                guard let option = target.options.first(where: { $0.id == id }),
                    case .select(_, let choices) = option.kind
                else { return refused(.missingOption) }
                guard choices.contains(where: { $0.value == value }) else { return refused(.unavailableValue) }
            }
            return exact(.setOptions, values)
        case .permissions(let source, let forbidden):
            guard let option = target.options.first(where: { $0.category == "mode" }),
                case .select(_, let choices) = option.kind
            else { return refused(.missingOption) }
            // Presentation mappings come from the plugin; do not reinterpret provider identifiers.
            let offered = choices.map(\.value).filter { value in
                let mapped = option.permissionMappings?[value] ?? value
                let available =
                    option.permissionMappings == nil || option.permissionMappings?[value] != nil
                    || value == "plan" || value == "read-only"
                let blocked = forbidden.contains { denied in
                    if denied == value || denied == mapped { return true }
                    if let effective = option.permissionEffectiveModes?[value],
                        TaskPermissionMode.migrating(denied) == effective
                    {
                        return true
                    }
                    guard let mode = TaskPermissionMode.migrating(mapped) else { return false }
                    return TaskPermissionMode.migrating(denied) == mode
                }
                return available && !blocked
            }
            guard let selection = AgentModelPermissions.selection(for: source, offered: offered, forbidden: forbidden)
            else { return refused(.noSafePermissions) }
            let values = [option.id: selection.value]
            if option.permissionMappings?[selection.value] != nil {
                guard let effective = option.permissionEffectiveModes?[selection.value],
                    let requested = source.flatMap(TaskPermissionMode.init(rawValue:))
                else { return fallback(.setOptions, .incomparablePermissions, values: values) }
                return effective == requested
                    ? exact(.setOptions, values, reason: .permissionEquivalent)
                    : fallback(.setOptions, .stricterPermission, values: values)
            }
            switch selection.reason {
            case .equivalent: return exact(.setOptions, values, reason: .permissionEquivalent)
            case .stricter: return fallback(.setOptions, .stricterPermission, values: values)
            case .safestAvailable, .unknown: return fallback(.setOptions, .incomparablePermissions, values: values)
            }
        case .steer:
            if target.negotiated?.steering == true {
                return target.steeringPolicy == .nonInterrupting
                    ? exact(.steer) : fallback(.steerAfterTools, .toolBoundary)
            }
            if target.steeringPolicy == .afterTools { return fallback(.interruptAfterTools, .toolBoundary) }
            return refused(.steeringUnavailable)
        }
    }
}
