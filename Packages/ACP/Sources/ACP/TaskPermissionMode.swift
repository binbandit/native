/// Native's task permission contract. Provider wire values stay in plugin mappings.
public enum TaskPermissionMode: String, CaseIterable, Codable, Hashable, Sendable {
    case askFirst = "ask-first"
    case acceptEdits = "accept-edits"
    case auto
    case fullAccess = "full-access"

    public var title: String {
        switch self {
        case .askFirst: "Ask first"
        case .acceptEdits: "Accept edits"
        case .auto: "Auto"
        case .fullAccess: "Full access"
        }
    }

    public var summary: String {
        switch self {
        case .askFirst: "Asks before edits and commands, subject to your permission rules."
        case .acceptEdits: "Allows file edits. Asks before other actions."
        case .auto: "Reviews actions automatically and asks when an action needs you."
        case .fullAccess: "The agent can run any command and change any file without asking."
        }
    }

    /// Legacy saved levels migrate conservatively; Plan remains a separate task mode.
    public static func migrating(_ value: String) -> Self? {
        if let mode = Self(rawValue: value) { return mode }
        switch value {
        case "default", "read-only", "dontAsk", "plan", "ask", "manual": return .askFirst
        case "acceptEdits", "workspace-write": return .acceptEdits
        case "agent": return .auto
        case "bypassPermissions", "agent-full-access", "danger-full-access": return .fullAccess
        default: return nil
        }
    }

    public var rank: Int { Self.allCases.firstIndex(of: self) ?? 0 }
}
