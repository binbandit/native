/// A conservative permission translation between ACP adapters. Only documented permission
/// semantics participate. Unknown modes cannot borrow another adapter's meaning by spelling.
public enum AgentModelPermissions {
    public static func replacement(for source: String, offered: [String], forbidden: Set<String> = []) -> String? {
        let candidates: [String]
        switch source {
        case "default", "read-only": candidates = ["read-only", "default"]
        case "acceptEdits", "workspace-write": candidates = ["read-only", "default"]
        case "auto", "agent": candidates = ["read-only", "default"]
        case "bypassPermissions", "agent-full-access": candidates = ["read-only", "default"]
        default: return nil
        }
        return candidates.first { offered.contains($0) && !forbidden.contains($0) }
    }
}
