/// A plugin's verified skill delivery mechanism. Future values retain the MCP compatibility path.
public enum NativeAgentSkillFormat: String, WireEnum {
    case claudeCode = "claude-code"
    case codex
    case unknown
}
