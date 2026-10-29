#if DEBUG
import ACP
import Foundation

/// Groups of tool work for previews, folded through `SessionState` from wire-shaped updates the way
/// the app receives Claude Code's.
enum ToolGroupPreviewFixtures {
    /// Finished groups: reads and searches only, a mixed one, and one with edits.
    static let done: [ToolWorkGroup] = [
        group([read("notes.txt"), read("ToolRow.swift"), grep("ToolPresentation")]),
        group([read("ToolRow.swift"), command("swift test --filter ToolWording"), edit("ToolRow.swift")]),
        group([edit("ToolRow.swift"), edit("ToolCallView.swift"), command("swift build")]),
    ]

    /// A group still at work: two reads done, a command running.
    static let running = group([
        read("ToolRow.swift"), read("ToolCallView.swift"), command("swift build", status: "in_progress"),
    ])

    /// A group whose newest item is the agent's reasoning.
    static let thinking = group(
        [read("ToolRow.swift"), grep("ToolLine")], thought: "Next I'll check how rows truncate.")

    /// A group that ended on a failed command, and one a stop cut short.
    static let troubled: [ToolWorkGroup] = [
        group([read("Package.swift"), command("swift test", status: "failed", exitCode: 1)]),
        group([read("Package.swift"), command("swift build", status: "in_progress")], endingWith: .cancelled),
    ]

    /// Thirty calls, more than an open group shows before it scrolls.
    static let long = group(
        (1...30).map { index in
            index.isMultiple(of: 5) ? command("swift test --filter Case\(index)") : read("File\(index).swift")
        })

    // MARK: - Building

    private static func group(
        _ updates: [String], thought: String? = nil, endingWith stopReason: StopReason? = nil
    ) -> ToolWorkGroup {
        var state = SessionState()
        state.appendUserMessage("Fix the tool rows")
        for update in updates {
            if let call: ToolCallUpdate = decode(update) { state.apply(.toolCall(call)) }
        }
        if let thought {
            state.apply(.agentThoughtChunk(ContentChunk(content: .text(thought))))
        }
        if let stopReason { state.endTurn(stopReason) }
        let rows = TranscriptRow.rows(from: state.items)
        for row in rows {
            if case .toolGroup(let group) = row { return group }
        }
        return ToolWorkGroup(items: [])
    }

    private static var next = 0

    private static func id() -> String {
        next += 1
        return "toolu_preview_\(next)"
    }

    private static func read(_ file: String) -> String {
        """
        {"toolCallId": "\(id())", "name": "Read", "title": "Read /Users/me/app/Sources/\(file)", "kind": "read",
         "status": "completed", "rawInput": {"file_path": "/Users/me/app/Sources/\(file)"},
         "content": [{"type": "content", "content": {"type": "text", "text": "```\\n1\\timport SwiftUI\\n```"}}]}
        """
    }

    private static func grep(_ pattern: String) -> String {
        """
        {"toolCallId": "\(id())", "name": "Grep", "title": "grep", "kind": "search", "status": "completed",
         "rawInput": {"pattern": "\(pattern)", "path": "/Users/me/app/Sources"},
         "content": [{"type": "content", "content": {"type": "text", "text": "Found 1 file\\nSources/ToolRow.swift"}}]}
        """
    }

    private static func edit(_ file: String) -> String {
        """
        {"toolCallId": "\(id())", "name": "Edit", "title": "Edit /Users/me/app/Sources/\(file)", "kind": "edit",
         "status": "completed",
         "content": [{"type": "diff", "path": "/Users/me/app/Sources/\(file)", "oldText": "let a = 1\\nlet b = 2\\n",
                      "newText": "let a = 10\\nlet b = 2\\nlet c = 3\\n"}]}
        """
    }

    private static func command(_ command: String, status: String = "completed", exitCode: Int? = nil) -> String {
        let output = exitCode.map { "Exit code \($0)\\nerror: 2 tests failed" } ?? "Build complete!"
        return """
            {"toolCallId": "\(id())", "name": "Bash", "title": "\(command)", "kind": "execute", "status": "\(status)",
             "rawInput": {"command": "\(command)", "description": "Run \(command)"},
             "content": [{"type": "content", "content": {"type": "text", "text": "```console\\n\(output)\\n```"}}]}
            """
    }

    private static func decode<T: Decodable>(_ json: String) -> T? {
        try? JSONDecoder().decode(T.self, from: Data(json.utf8))
    }
}
#endif
