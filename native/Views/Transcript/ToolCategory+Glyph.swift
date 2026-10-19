import ACP

extension ToolCategory {
    /// The design system's glyph for the category.
    var glyph: DSToolGlyph {
        switch self {
        case .read: .read
        case .search: .search
        case .edit: .edit
        case .command: .command
        case .web: .web
        case .mcp: .mcp
        case .think: .think
        case .subagent: .subagent
        case .other: .other
        }
    }
}
