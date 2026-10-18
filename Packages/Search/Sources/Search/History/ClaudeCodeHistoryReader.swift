import Foundation

/// Claude Code's history: one JSONL file per session in `~/.claude/projects/<folder>/<id>.jsonl`.
///
/// The records search reads (verified against Claude Code 2.x files):
/// - `user`: `message.content` is the prompt (a string, or `text` blocks) or `tool_result` blocks
///   (`tool_use_id`, `content` as a string or `text` blocks). `isMeta` marks injected context.
/// - `assistant`: one content block per record: `text`, `thinking` (`thinking`), or `tool_use`
///   (`id`, `name`, `input`). Blocks of one reply share `message.id`.
/// - `ai-title` (`aiTitle`), `custom-title` (`customTitle`, the user's rename, which wins) and the
///   older `summary` (`summary`) name the session.
/// Every conversation record carries `cwd`, `sessionId` and `timestamp`. `isSidechain` records
/// belong to subagents, which live in `<id>/subagents/` and aren't indexed as their own tasks.
/// Everything else (`api-request*`, `attachment`, `file-history-*`, `queue-operation`, …) is skipped
/// before it's parsed.
public struct ClaudeCodeHistoryReader: SessionHistoryReader {
    public let root: URL

    public init(root: URL) {
        self.root = root
    }

    /// `~/.claude/projects`, or `$CLAUDE_CONFIG_DIR/projects` when the user moved it.
    public static func standard(environment: [String: String] = ProcessInfo.processInfo.environment) -> Self {
        let base =
            environment["CLAUDE_CONFIG_DIR"].map { URL(filePath: $0, directoryHint: .isDirectory) }
            ?? URL.homeDirectory.appending(path: ".claude", directoryHint: .isDirectory)
        return Self(root: base.appending(path: "projects", directoryHint: .isDirectory))
    }

    public func sources() -> [HistorySource] {
        // Sessions sit in a folder per project; deeper files are subagents' and tools' own logs.
        HistorySource.jsonlFiles(under: root, maxDepth: 2)
    }

    public func read(_ source: HistorySource) throws -> HistorySession? {
        var builder = HistoryTranscriptBuilder()
        var sessionID = source.url.deletingPathExtension().lastPathComponent
        var cwd: String?
        var aiTitle: String?
        var customTitle: String?
        var summary: String?
        var firstDate: Date?
        var lastDate: Date?
        let markers = [
            #""type":"user""#, #""type":"assistant""#, #""type":"ai-title""#, #""type":"custom-title""#,
            #""type":"summary""#,
        ]
        try JSONLines.forEach(in: source.url, containing: markers) { record in
            switch record["type"] as? String {
            case "ai-title": aiTitle = record["aiTitle"] as? String ?? aiTitle
            case "custom-title": customTitle = record["customTitle"] as? String ?? customTitle
            case "summary": summary = record["summary"] as? String ?? summary
            case let type? where type == "user" || type == "assistant":
                guard record["isSidechain"] as? Bool != true, record["isMeta"] as? Bool != true,
                    let message = record["message"] as? [String: Any]
                else { return }
                let date = JSONLines.date(record["timestamp"])
                firstDate = firstDate ?? date
                lastDate = date ?? lastDate
                cwd = cwd ?? record["cwd"] as? String
                if let id = record["sessionId"] as? String {
                    sessionID = id
                }
                if type == "user" {
                    readUser(message["content"], date: date, into: &builder)
                } else {
                    readAssistant(message["content"], date: date, into: &builder)
                }
            default:
                break
            }
        }
        guard let cwd, !builder.documents.isEmpty else { return nil }
        return HistorySession(
            sessionID: sessionID, title: customTitle ?? aiTitle ?? summary, cwd: cwd, createdAt: firstDate,
            updatedAt: lastDate, documents: builder.documents)
    }

    private func readUser(_ content: Any?, date: Date?, into builder: inout HistoryTranscriptBuilder) {
        if let text = content as? String {
            if !HistoryTranscriptBuilder.isInjectedContext(text) {
                builder.message(.user, text, date: date)
            }
            return
        }
        for block in content as? [[String: Any]] ?? [] {
            switch block["type"] as? String {
            case "text":
                if let text = block["text"] as? String, !HistoryTranscriptBuilder.isInjectedContext(text) {
                    builder.message(.user, text, date: date)
                }
            case "tool_result":
                guard let id = block["tool_use_id"] as? String else { continue }
                builder.toolOutput(id: id, output: Self.text(of: block["content"]))
            default:
                break
            }
        }
    }

    private func readAssistant(_ content: Any?, date: Date?, into builder: inout HistoryTranscriptBuilder) {
        for block in content as? [[String: Any]] ?? [] {
            switch block["type"] as? String {
            case "text":
                builder.message(.agent, block["text"] as? String ?? "", date: date)
            case "thinking":
                builder.message(.thought, block["thinking"] as? String ?? "", date: date)
            case "tool_use":
                guard let id = block["id"] as? String, let name = block["name"] as? String else { continue }
                let input = block["input"] as? [String: Any] ?? [:]
                if name == "TodoWrite", let todos = input["todos"] as? [[String: Any]] {
                    builder.plan(todos.compactMap { $0["content"] as? String }, date: date)
                }
                let editsFiles = ["Edit", "MultiEdit", "Write", "NotebookEdit"].contains(name)
                builder.toolCall(id: id, name: name, input: JSONLines.strings(in: input), date: date, hasDiff: editsFiles)
            default:
                break
            }
        }
    }

    /// A tool result's text: a string, or the text of its blocks (images are skipped).
    static func text(of content: Any?) -> String {
        if let string = content as? String { return string }
        let blocks = content as? [[String: Any]] ?? []
        return blocks.compactMap { $0["type"] as? String == "text" ? $0["text"] as? String : nil }
            .joined(separator: "\n")
    }
}
