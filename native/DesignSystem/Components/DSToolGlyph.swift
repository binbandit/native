import SwiftUI

/// The glyph for each kind of tool work, the same wherever a tool call shows: transcript rows, the
/// condensed list of a long run, its count breakdown. Hierarchical outline symbols in the row's
/// text color, so they read in light, dark and True Black alike.
public enum DSToolGlyph: String, CaseIterable, Sendable {
    /// Reading or viewing a file, or listing files.
    case read
    /// Searching files or their contents.
    case search
    /// Writing, editing, creating, moving or deleting files.
    case edit
    /// Running a shell command.
    case command
    /// Fetching a page or searching the web.
    case web
    /// A tool an MCP server provides.
    case mcp
    /// Thinking or planning.
    case think
    /// Work handed to a subagent.
    case subagent
    case other
    /// Several kinds of work together, for a line that stands for them all.
    case mixed

    public var systemImage: String {
        switch self {
        case .read: "doc.text"
        case .search: "magnifyingglass"
        case .edit: "pencil"
        case .command: "terminal"
        case .web: "globe"
        case .mcp: "puzzlepiece.extension"
        case .think: "brain"
        case .subagent: "sparkles"
        case .other: "wrench.and.screwdriver"
        case .mixed: "square.stack.3d.up"
        }
    }

    /// What the glyph stands for, for accessibility and tooltips ("3 reads").
    public func count(_ count: Int) -> String {
        let (singular, plural) =
            switch self {
            case .read: ("read", "reads")
            case .search: ("search", "searches")
            case .edit: ("edit", "edits")
            case .command: ("command", "commands")
            case .web: ("web request", "web requests")
            case .mcp: ("MCP call", "MCP calls")
            case .think: ("plan", "plans")
            case .subagent: ("subagent", "subagents")
            case .other: ("other tool", "other tools")
            case .mixed: ("tool call", "tool calls")
            }
        return "\(count) \(count == 1 ? singular : plural)"
    }
}

#Preview("Tool glyphs") {
    DSPreviewPair {
        HStack(spacing: DS.Space.lg) {
            ForEach(DSToolGlyph.allCases, id: \.self) { glyph in
                Image(systemName: glyph.systemImage)
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.dsTextSecondary)
                    .help(glyph.rawValue)
            }
        }
        .font(.dsBody)
    }
}
