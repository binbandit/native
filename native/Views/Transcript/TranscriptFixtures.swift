#if DEBUG
import ACP
import Foundation

/// Sample transcript data for previews, shaped like real Claude Code adapter traffic.
///
/// ACP's memberwise initializers are internal to the package, so values are decoded from wire JSON
/// or folded through `SessionState`, the same way the app receives them.
enum TranscriptFixtures {
    static let markdown = """
        ## Refactor summary

        I split the parser into **two passes** and moved the `Tokenizer` into its own file. See the \
        [ACP spec](https://agentclientprotocol.com) for the message shapes.

        1. Tokenize the input
        2. Build the block tree
           - group runs by their innermost block
           - keep nested lists indented
        3. Render

        > Partial fences render as code while they stream in.

        ```swift
        let blocks = MarkdownNode.blocks(from: source)
        for block in blocks ?? [] {
            print(block.kind)
        }
        ```

        | File | Lines | Status |
        |------|------:|:------:|
        | `Parser.swift` | 214 | Done |
        | `Tokenizer.swift` | 96 | New |

        ---

        Streaming text with an unclosed fence:

        ```py
        def main():
            print("hello")
        """

    static let messages: [TranscriptMessage] = {
        var state = SessionState()
        state.appendUserMessage("Read notes.txt, then create a file named out.txt containing the word done, then run `ls` with bash.")
        state.apply(.agentThoughtChunk(ContentChunk(content: .text(
            "The user wants three steps. I'll read the file first, then write `out.txt`, then list the directory."
        ))))
        state.apply(.agentMessageChunk(ContentChunk(content: .text(
            "All three done. `notes.txt` contains \"hello\", `out.txt` now contains \"done\", and `ls` shows **both files**."
        ))))
        return state.items.compactMap { item in
            if case .message(let message) = item { message } else { nil }
        }
    }()

    /// Claude Code's AskUserQuestion, captured from claude-agent-acp 0.93: waiting for the user,
    /// answered, and skipped.
    static let askedQuestions: [ToolCallState] = {
        var waiting = SessionState(), answered = SessionState(), skipped = SessionState()
        for update in [askAnnounced, askQuestions] {
            waiting.apply(.toolCallUpdate(decode(update)))
            answered.apply(.toolCallUpdate(decode(update)))
            skipped.apply(.toolCallUpdate(decode(update)))
        }
        answered.apply(.toolCallUpdate(decode(askAnswered)))
        answered.apply(.toolCallUpdate(decode(askCompleted)))
        skipped.apply(.toolCallUpdate(decode(askSkipped)))
        skipped.apply(.toolCallUpdate(decode(askCompleted)))
        return [waiting, answered, skipped].flatMap { state in
            state.items.compactMap { item in
                if case .toolCall(let call) = item { call } else { nil }
            }
        }
    }()

    static let notices: [TranscriptNotice] = {
        var state = SessionState()
        state.appendNotice("Stopped.", isError: false)
        state.appendNotice("Stopped: the response hit the token limit.", isError: true)
        return state.items.compactMap { item in
            if case .notice(let notice) = item { notice } else { nil }
        }
    }()

    static let toolCalls: [ToolCallState] = {
        var state = SessionState()
        let updates = [
            readUpdate, grepUpdate, globUpdate, writeUpdate, bashRunningUpdate, bashUpdate, editUpdate,
            taskUpdate, mcpUpdate, mcpPendingUpdate, failedBashUpdate, failedUpdate,
        ]
        for update in updates {
            state.apply(.toolCall(decode(update)))
        }
        state.requestPermission(decode(permission(for: "toolu_write", options: editOptions)), id: .int(0))
        state.requestPermission(decode(permission(for: "toolu_mcp_pending", options: mcpOptions)), id: .int(1))
        return state.items.compactMap { item in
            if case .toolCall(let call) = item { call } else { nil }
        }
    }()

    static let plan: [PlanEntry] = decode("""
        [
          {"content": "Read notes.txt", "priority": "high", "status": "completed"},
          {"content": "Create out.txt containing \\"done\\"", "priority": "high", "status": "completed"},
          {"content": "Run ls to confirm both files exist", "priority": "medium", "status": "in_progress"},
          {"content": "Summarize the results", "priority": "low", "status": "pending"},
          {"content": "Clean up temporary files", "priority": "low", "status": "pending"}
        ]
        """)

    static var editDiff: FileDiff { diff(in: editUpdate) }
    static var newFileDiff: FileDiff { diff(in: writeUpdate) }

    // MARK: - Wire JSON

    private static let readUpdate = """
        {"toolCallId": "toolu_read", "name": "Read", "title": "Read /private/tmp/acp-research/sandbox/notes.txt", "kind": "read",
         "status": "completed", "rawInput": {"file_path": "/private/tmp/acp-research/sandbox/notes.txt"},
         "content": [{"type": "content", "content": {"type": "text", "text": "```\\n1\\thello\\n```"}}]}
        """

    private static let writeUpdate = """
        {"toolCallId": "toolu_write", "name": "Write", "title": "Write /private/tmp/acp-research/sandbox/out.txt", "kind": "edit",
         "status": "pending", "rawInput": {"file_path": "/private/tmp/acp-research/sandbox/out.txt", "content": "done\\n"},
         "content": [{"type": "diff", "path": "/private/tmp/acp-research/sandbox/out.txt", "oldText": null, "newText": "done\\n"}]}
        """

    private static let editOptions = """
        {"optionId": "allow-once", "name": "Yes", "kind": "allow_once"},
        {"optionId": "allow-always", "name": "Yes, allow all edits in sandbox/ during this session", "kind": "allow_always"},
        {"optionId": "reject-once", "name": "No", "kind": "reject_once"}
        """

    private static let mcpOptions = """
        {"optionId": "allow-once", "name": "Allow", "kind": "allow_once"},
        {"optionId": "allow-always", "name": "Always allow", "kind": "allow_always"},
        {"optionId": "reject-once", "name": "Deny", "kind": "reject_once"}
        """

    private static func permission(for toolCallID: String, options: String) -> String {
        """
        {"sessionId": "59be18cd-5e67-47b1-8562-9996457a07e9", "toolCall": {"toolCallId": "\(toolCallID)"}, "options": [\(options)]}
        """
    }

    private static let grepUpdate = """
        {"toolCallId": "toolu_grep", "name": "Grep", "title": "grep \\"MarkdownNode\\" Sources/Views", "kind": "search",
         "status": "completed", "rawInput": {"pattern": "MarkdownNode", "path": "/Users/me/Developer/app/Sources/Views"},
         "content": [{"type": "content", "content": {"type": "text", "text": "Found 2 files\\nSources/Views/MarkdownView.swift\\nSources/Views/ToolCallView.swift"}}]}
        """

    private static let globUpdate = """
        {"toolCallId": "toolu_glob", "name": "Glob", "title": "Find `**/*View.swift`", "kind": "search", "status": "completed",
         "rawInput": {"pattern": "**/*View.swift"},
         "content": [{"type": "content", "content": {"type": "text", "text": "Sources/Views/DiffView.swift\\nSources/Views/PlanView.swift"}}]}
        """

    private static let taskUpdate = """
        {"toolCallId": "toolu_task", "name": "Task", "title": "Audit the transcript views", "kind": "think", "status": "pending",
         "rawInput": {"description": "Audit the transcript views", "prompt": "Check every view for HIG issues."}}
        """

    private static let mcpUpdate = """
        {"toolCallId": "toolu_mcp", "name": "mcp__linear__search_issues", "title": "mcp__linear__search_issues", "kind": "other",
         "status": "completed", "rawInput": {"query": "transcript rendering", "limit": 3},
         "content": [{"type": "content", "content": {"type": "text", "text": "NAT-42  Render tool calls like Factory\\nNAT-57  Streaming Markdown flickers"}}]}
        """

    private static let mcpPendingUpdate = """
        {"toolCallId": "toolu_mcp_pending", "name": "mcp__github__create_pull_request", "title": "mcp__github__create_pull_request",
         "kind": "other", "status": "pending",
         "rawInput": {"title": "fix(transcript): Factory-style tool rows", "base": "main", "draft": false}}
        """

    private static let failedBashUpdate = """
        {"toolCallId": "toolu_bash_failed", "name": "Bash", "title": "swift test", "kind": "execute", "status": "failed",
         "rawInput": {"command": "swift test --filter TranscriptTests", "description": "Run the transcript tests"},
         "content": [{"type": "content", "content": {"type": "text", "text": "```console\\nerror: no tests found; create a target in the 'Tests' directory\\n```"}}]}
        """

    private static let bashRunningUpdate = """
        {"toolCallId": "toolu_bash_running", "name": "Bash", "title": "swift build -c release", "kind": "execute", "status": "in_progress",
         "rawInput": {"command": "swift build -c release", "description": "Build the package in release mode"},
         "content": [{"type": "content", "content": {"type": "text", "text": "Build the package in release mode"}}]}
        """

    private static let bashUpdate = """
        {"toolCallId": "toolu_bash", "name": "Bash", "title": "ls", "kind": "execute", "status": "completed",
         "rawInput": {"command": "ls", "description": "List files in current directory"},
         "content": [{"type": "content", "content": {"type": "text", "text": "```console\\nnotes.txt\\nout.txt\\n```"}}]}
        """

    private static let editUpdate: String = {
        let old = (1...30).map { "let value\($0) = \($0)" }.joined(separator: "\n") + "\n"
        let new = old
            .replacingOccurrences(of: "let value4 = 4\n", with: "let value4 = 40\nlet extra = true\n")
            .replacingOccurrences(of: "let value22 = 22\n", with: "")
        return """
            {"toolCallId": "toolu_edit", "name": "Edit", "title": "Edit /Users/me/Developer/app/Sources/Values.swift", "kind": "edit",
             "status": "completed",
             "content": [{"type": "diff", "path": "/Users/me/Developer/app/Sources/Values.swift",
                          "oldText": \(json(old)), "newText": \(json(new))}]}
            """
    }()

    private static let failedUpdate = """
        {"toolCallId": "toolu_fetch", "name": "WebFetch", "title": "Fetch https://example.com/docs", "kind": "fetch", "status": "failed",
         "rawInput": {"url": "https://example.com/docs", "prompt": "Summarize the page"}}
        """

    // MARK: - Helpers

    private static let askAnnounced = """
        {"_meta":{"claudeCode":{"toolName":"AskUserQuestion"}},"toolCallId":"toolu_016PGc48eyfVKaczjHf1iguq","name":"AskUserQuestion","rawInput":{},"status":"pending","title":"Asking for your input","kind":"other","content":[]}
        """
    private static let askQuestions = """
        {"_meta":{"claudeCode":{"toolName":"AskUserQuestion"}},"toolCallId":"toolu_016PGc48eyfVKaczjHf1iguq","rawInput":{"questions":[{"question":"Which color do you prefer?","header":"Color","multiSelect":false,"options":[{"label":"Red","description":"A warm, bold color"},{"label":"Blue","description":"A cool, calm color"}]},{"question":"Which sizes should ship?","header":"Sizes","multiSelect":true,"options":[{"label":"Small","description":"For phones"},{"label":"Large","description":"For desktops"}]}]},"title":"Which color do you prefer?"}
        """
    private static let askAnswered = """
        {"_meta":{"claudeCode":{"toolResponse":{"questions":[{"question":"Which color do you prefer?","header":"Color","options":[{"label":"Red","description":"A warm, bold color"},{"label":"Blue","description":"A cool, calm color"}],"multiSelect":false},{"question":"Which sizes should ship?","header":"Sizes","options":[{"label":"Small","description":"For phones"},{"label":"Large","description":"For desktops"}],"multiSelect":true}],"answers":{"Which color do you prefer?":"Red","Which sizes should ship?":"Small, Large"},"annotations":{"Which color do you prefer?":{"notes":"Matches the logo"}}},"toolName":"AskUserQuestion"}},"toolCallId":"toolu_016PGc48eyfVKaczjHf1iguq"}
        """
    private static let askSkipped = """
        {"_meta":{"claudeCode":{"toolResponse":{"questions":[{"question":"Which color do you prefer?","header":"Color","options":[],"multiSelect":false}],"answers":{}},"toolName":"AskUserQuestion"}},"toolCallId":"toolu_016PGc48eyfVKaczjHf1iguq"}
        """
    private static let askCompleted = """
        {"_meta":{"claudeCode":{"toolName":"AskUserQuestion"}},"toolCallId":"toolu_016PGc48eyfVKaczjHf1iguq","status":"completed","rawOutput":"Your questions have been answered."}
        """

    private static func decode<T: Decodable>(_ json: String) -> T {
        do {
            return try JSONDecoder().decode(T.self, from: Data(json.utf8))
        } catch {
            fatalError("Invalid fixture JSON: \(error)")
        }
    }

    private static func diff(in update: String) -> FileDiff {
        let call: ToolCallUpdate = decode(update)
        guard case .diff(let diff) = call.content?.first else { fatalError("Fixture has no diff") }
        return diff
    }

    private static func json(_ string: String) -> String {
        String(decoding: (try? JSONEncoder().encode(string)) ?? Data(), as: UTF8.self)
    }
}
#endif
