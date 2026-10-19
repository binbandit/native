import Foundation

/// What kind of work a tool call does, as a client shows it at a glance: one glyph per category,
/// the same for every agent.
public enum ToolCategory: String, CaseIterable, Hashable, Sendable {
    /// Reading or viewing a file, or listing files.
    case read
    /// Searching files or their contents (grep, glob, find).
    case search
    /// Writing, editing, creating, moving or deleting files.
    case edit
    /// Running a shell command.
    case command
    /// Fetching a URL or searching the web.
    case web
    /// A tool an MCP server provides.
    case mcp
    /// Thinking, planning, or switching modes.
    case think
    /// Handing work to a subagent.
    case subagent
    case other
}

extension ToolCallState {
    /// The call's category, from the tool's name when the agent sends one (Claude Code), otherwise
    /// its ACP kind refined by its title (codex-acp files a web search under `search`, an MCP call
    /// under `execute`).
    public var category: ToolCategory {
        if mcpTool != nil { return .mcp }
        if let name, let category = Self.categories[name] { return category }
        switch kind {
        case .read: return .read
        case .search: return Self.isWebSearch(title) ? .web : .search
        case .edit, .delete, .move: return .edit
        case .execute: return .command
        case .fetch: return .web
        case .think, .switchMode: return .think
        case .other: return Self.category(ofTitle: title)
        }
    }

    /// Claude Code's tools, by name.
    private static let categories: [String: ToolCategory] = [
        "Read": .read, "NotebookRead": .read, "LS": .read,
        "Grep": .search, "Glob": .search, "ToolSearch": .search,
        "Edit": .edit, "MultiEdit": .edit, "Write": .edit, "NotebookEdit": .edit,
        "Bash": .command, "BashOutput": .command, "KillShell": .command, "KillBash": .command,
        "WebFetch": .web, "WebSearch": .web,
        "TodoWrite": .think, "ExitPlanMode": .think, "EnterPlanMode": .think,
        "Task": .subagent, "Agent": .subagent,
    ]

    /// codex-acp titles its web searches `Web search: …`, `Open page: …` and `Find in page …`.
    private static func isWebSearch(_ title: String) -> Bool {
        ["Web search", "Open page", "Find in page"].contains { title.hasPrefix($0) }
    }

    /// For agents that file everything under `other`: the verb their title starts with.
    private static func category(ofTitle title: String) -> ToolCategory {
        let verb = title.prefix { $0.isLetter }.lowercased()
        switch verb {
        case "read", "view", "open", "list", "cat": return .read
        case "search", "grep", "find", "glob": return .search
        case "edit", "write", "create", "update", "delete", "remove", "rename", "move", "apply", "patch": return .edit
        case "run", "execute", "exec", "bash", "shell", "terminal": return .command
        case "fetch", "browse", "download", "curl": return .web
        case "think", "plan", "reason": return .think
        default: return isWebSearch(title) ? .web : .other
        }
    }
}
