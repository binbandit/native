import Foundation

/// Polls have their own ACP IDs, but their results belong to the process they wait on. Build a
/// presentation copy so replay and grouping preferences never change the captured transcript.
enum ToolPollingTranscript {
    static func folding(_ items: [TranscriptItem]) -> [TranscriptItem] {
        var result: [TranscriptItem] = []
        var commands: [String: Int] = [:]
        for item in items {
            guard case .toolCall(let call) = item else {
                result.append(item)
                // Process IDs can be reused between turns. Never attach across a prose boundary.
                if case .message(let message) = item, message.role != .thought { commands.removeAll() }
                continue
            }
            if call.isPolling, call.permission == nil, let session = polledSession(call),
                let index = commands[session], case .toolCall(var command) = result[index]
            {
                append(call, to: &command)
                result[index] = .toolCall(command)
                if call.status.isFinished && runningSession(call) == nil { commands[session] = nil }
                continue
            }
            if !call.isPolling, call.mcpTool == nil, let session = runningSession(call) {
                commands[session] = result.count
            }
            result.append(item)
        }
        return result
    }

    private static func polledSession(_ call: ToolCallState) -> String? {
        if let program = CodeModeProgram(call) {
            return program.polledSessions.count == 1 ? program.polledSessions.first : nil
        }
        guard call.name == "write_stdin" || call.title == "write_stdin" else { return nil }
        let input = call.rawInput?["arguments"] ?? call.rawInput
        return input?["session_id"]?.stringValue ?? input?["session_id"]?.intValue.map(String.init)
    }

    private static func runningSession(_ call: ToolCallState) -> String? {
        let text = outputText(call)
        // A multi-command program may return several sessions. Keep it intact rather than guess.
        let patterns = [
            #"Process running with session ID\s+(\d+)"#,
            #""session_id"\s*:\s*"?(\d+)"?"#,
        ]
        var sessions: Set<String> = []
        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern) else { continue }
            for match in regex.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
                if let range = Range(match.range(at: 1), in: text) { sessions.insert(String(text[range])) }
            }
        }
        return sessions.count == 1 ? sessions.first : nil
    }

    private static func append(_ poll: ToolCallState, to command: inout ToolCallState) {
        // Materialize each source's fallback output before joining content: clients prefer content
        // over terminal/raw output, and would otherwise mask a chunk from the other source.
        command.content = outputBlocks(command) + outputBlocks(poll)
        if let output = poll.terminalOutput { command.terminalOutput = (command.terminalOutput ?? "") + output }
        if let output = poll.rawOutput { command.rawOutput = output }
        let exit =
            poll.exitCode ?? capture(#"Process exited with code\s+(-?\d+)"#, in: outputText(poll)).flatMap(Int.init)
        if let exit {
            command.meta = (command.meta ?? .object([:])).merging(
                .object(["terminal_exit": .object(["exit_code": .number(Double(exit))])]))
        }
        let running = !poll.status.isFinished || runningSession(poll) != nil
        command.status = (exit ?? 0) != 0 ? .failed : running ? .inProgress : poll.status
        command.finishedAt = running ? nil : poll.finishedAt
    }

    private static func outputBlocks(_ call: ToolCallState) -> [ToolCallContent] {
        if call.content.contains(where: { if case .content(let block) = $0 { block.text != nil } else { false } }) {
            return call.content
        }
        if let text = call.terminalOutput { return call.content + [.content(.text(text))] }
        if let output = call.rawOutput {
            return call.content + [
                .content(.text(output["output"]?.stringValue ?? output.stringValue ?? output.prettyPrinted()))
            ]
        }
        return call.content
    }

    private static func outputText(_ call: ToolCallState) -> String {
        let text = call.content.compactMap { content -> String? in
            if case .content(let block) = content { block.text } else { nil }
        }
        return (text + [call.terminalOutput, call.rawOutput?.prettyPrinted()].compactMap { $0 }).joined(separator: "\n")
    }

    static func capture(_ pattern: String, in text: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern),
            let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
            let range = Range(match.range(at: 1), in: text)
        else { return nil }
        return String(text[range])
    }
}
