import ACP
import Foundation

/// How a tool call reads as one transcript row: its sentence from the shared wording
/// (`ToolCallWording`, the same on the Mac, the iPad and the phone), its category's glyph, the lines
/// an edit changed, and what its detail panel shows.
struct ToolPresentation {
    enum Body: Equatable {
        /// Content blocks as the agent sent them, or the raw input when there are none.
        case generic
        /// A shell command and its output.
        case command(String)
        /// Plain output lines, like search results; Markdown would join them into one paragraph.
        case lines
        /// MCP input and output, split by a hairline, under the tool's name as the agent sent it.
        case mcp(rawName: String)
        /// The file diffs of an edit.
        case diff
    }

    let wording: ToolCallWording
    let phase: ToolPhase
    let exitCode: Int?
    let glyph: DSToolGlyph
    let body: Body

    /// `root` is the task's folder, which a search of it needn't name (`ToolCallWording.relative(to:)`).
    init(_ call: ToolCallState, root: String? = nil) {
        wording = call.wording.relative(to: root)
        phase = ToolPhase(call)
        exitCode = call.exitCode
        // The wording's category: a command that only reads shows the read glyph.
        glyph = wording.category.glyph
        body =
            if let mcp = call.mcpTool {
                .mcp(rawName: mcp.rawName)
            } else if let command = wording.command {
                .command(command)
            } else {
                switch call.category {
                case .command: .command(call.shellCommand ?? call.title)
                case .edit: .diff
                case .search: .lines
                case .read, .web, .mcp, .think, .subagent, .other: .generic
                }
            }
    }

    /// "Reading notes.txt", "Ran swift test".
    var sentence: String {
        wording.sentence(for: phase, exitCode: exitCode)
    }

    /// The same sentence as a request, for an approval: "Edit notes.txt".
    var request: String {
        wording.sentence(for: .awaitingApproval)
    }

    var stats: DiffStats? {
        wording.lineChanges.map { DiffStats(added: $0.added, removed: $0.removed) }
    }

    /// How the call ended when it didn't simply succeed ("Exit 1", "Rejected").
    var outcome: String? {
        phase.outcome(exitCode: exitCode)
    }
}
