import Foundation

/// Codex's history: one rollout file per thread in
/// `~/.codex/sessions/YYYY/MM/DD/rollout-<time>-<thread id>.jsonl`, with thread names in
/// `~/.codex/session_index.jsonl` (`id`, `thread_name`, `updated_at`; the last line for an id wins).
///
/// The records search reads (verified against Codex CLI 0.1xx rollouts): each line is
/// `{timestamp, type, payload}`.
/// - `session_meta`: `payload.id` (the thread id ACP uses), `cwd`, `timestamp`.
/// - `response_item` with `payload.type`:
///   - `message`: `role` `user` or `assistant`, `content` blocks (`input_text`/`output_text` with
///     `text`). `developer` messages and user messages that are injected context
///     (`<environment_context>`, AGENTS.md) are skipped.
///   - `reasoning`: `summary` blocks (`summary_text`); the rest is encrypted and skipped.
///   - `function_call` (`call_id`, `name`, `arguments` as a JSON string) and `custom_tool_call`
///     (`call_id`, `name`, `input` as raw text, such as `apply_patch`'s patch), with their
///     `function_call_output`/`custom_tool_call_output` (`output` as a string or text blocks).
///     `update_plan` carries the plan (`plan[].step`).
/// `event_msg` records repeat the same conversation for the TUI and are skipped. Archived threads
/// (`~/.codex/archived_sessions/*.jsonl.zst`) are zstd-compressed and not read yet.
public struct CodexHistoryReader: SessionHistoryReader {
    public let root: URL
    /// The thread names file, or nil to name threads by their first prompt.
    public let index: URL?

    public init(root: URL, index: URL?) {
        self.root = root
        self.index = index
    }

    /// `~/.codex`, or `$CODEX_HOME` when the user moved it.
    public static func standard(environment: [String: String] = ProcessInfo.processInfo.environment) -> Self {
        let home =
            environment["CODEX_HOME"].map { URL(filePath: $0, directoryHint: .isDirectory) }
            ?? URL.homeDirectory.appending(path: ".codex", directoryHint: .isDirectory)
        return Self(
            root: home.appending(path: "sessions", directoryHint: .isDirectory),
            index: home.appending(path: "session_index.jsonl"))
    }

    public func sources() -> [HistorySource] {
        HistorySource.jsonlFiles(under: root)
    }

    public func read(_ source: HistorySource, resuming resume: HistoryResume?) throws -> HistoryRead {
        var builder = HistoryTranscriptBuilder()
        var sessionID = resume?.sessionID
        var cwd = resume?.cwd
        var createdAt: Date?
        var lastDate: Date?
        var firstPrompt: String?
        let markers = [#""type":"session_meta""#, #""type":"response_item""#]
        let offset = try JSONLines.forEach(in: source.url, from: resume?.offset ?? 0, containing: markers) { record in
            guard let payload = record["payload"] as? [String: Any] else { return }
            let date = JSONLines.date(record["timestamp"])
            switch record["type"] as? String {
            case "session_meta":
                sessionID = sessionID ?? payload["id"] as? String
                cwd = cwd ?? payload["cwd"] as? String
                createdAt = createdAt ?? JSONLines.date(payload["timestamp"]) ?? date
            case "response_item":
                lastDate = date ?? lastDate
                if let prompt = readItem(payload, date: date, into: &builder), firstPrompt == nil {
                    firstPrompt = prompt
                }
            default:
                break
            }
        }
        guard let sessionID, let cwd, resume != nil || !builder.documents.isEmpty else {
            return HistoryRead(session: nil, offset: offset)
        }
        // Thread names change as a thread goes on; a resumed read picks up a new one too.
        let title =
            threadNames()[sessionID]
            ?? firstPrompt.map { String(SearchText.collapsingWhitespace($0).prefix(80)) }
        let session = HistorySession(
            sessionID: sessionID, title: title, cwd: cwd, createdAt: createdAt, updatedAt: lastDate ?? createdAt,
            documents: builder.documents)
        return HistoryRead(session: session, offset: offset)
    }

    /// Adds one response item; returns the text when it's a prompt the user typed.
    private func readItem(_ item: [String: Any], date: Date?, into builder: inout HistoryTranscriptBuilder) -> String? {
        switch item["type"] as? String {
        case "message":
            let text = (item["content"] as? [[String: Any]] ?? []).compactMap { $0["text"] as? String }
                .joined(separator: "\n")
            switch item["role"] as? String {
            case "user":
                guard !HistoryTranscriptBuilder.isInjectedContext(text) else { return nil }
                builder.message(.user, text, date: date)
                return text
            case "assistant":
                builder.message(.agent, text, date: date)
            default:
                break
            }
        case "reasoning":
            let summary = (item["summary"] as? [[String: Any]] ?? []).compactMap { $0["text"] as? String }
            builder.message(.thought, summary.joined(separator: "\n\n"), date: date)
        case "function_call":
            guard let id = item["call_id"] as? String, let name = item["name"] as? String else { return nil }
            let arguments = (item["arguments"] as? String).flatMap { $0.data(using: .utf8) }
                .flatMap { try? JSONSerialization.jsonObject(with: $0) }
            if name == "update_plan", let plan = (arguments as? [String: Any])?["plan"] as? [[String: Any]] {
                builder.plan(plan.compactMap { $0["step"] as? String }, date: date)
            }
            let input = arguments.map { JSONLines.strings(in: $0) } ?? [item["arguments"] as? String ?? ""]
            builder.toolCall(id: id, name: name, input: input, date: date)
        case "custom_tool_call":
            guard let id = item["call_id"] as? String, let name = item["name"] as? String else { return nil }
            builder.toolCall(
                id: id, name: name, input: [item["input"] as? String ?? ""], date: date, hasDiff: name == "apply_patch")
        case "function_call_output", "custom_tool_call_output":
            guard let id = item["call_id"] as? String else { return nil }
            builder.toolOutput(id: id, output: ClaudeCodeHistoryReader.text(of: Self.outputText(item["output"])))
        default:
            break
        }
        return nil
    }

    /// Output as a string or as `input_text`/`output_text` blocks.
    private static func outputText(_ output: Any?) -> Any? {
        guard let blocks = output as? [[String: Any]] else { return output }
        return blocks.compactMap { $0["text"] as? String }.joined(separator: "\n")
    }

    private func threadNames() -> [String: String] {
        guard let index, FileManager.default.fileExists(atPath: index.path(percentEncoded: false)) else { return [:] }
        var names: [String: String] = [:]
        try? JSONLines.forEach(in: index, containing: [#""thread_name""#]) { record in
            if let id = record["id"] as? String, let name = record["thread_name"] as? String, !name.isEmpty {
                names[id] = name
            }
        }
        return names
    }
}
