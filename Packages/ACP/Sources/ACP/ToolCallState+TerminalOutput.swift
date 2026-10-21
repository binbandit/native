import Foundation

extension ToolCallState {
    /// Appends the output chunk an update carries and returns the rest of its `_meta`.
    ///
    /// codex-acp 2.2.2 sends a command's output only as `_meta.terminal_output_delta` chunks to a
    /// client that has no terminals: one per piece while it runs, or the whole output once when a
    /// loaded session replays it. Each chunk replaces the last in a merged `_meta`, so they're kept
    /// here instead, in order.
    mutating func appendingTerminalOutput(_ meta: JSONValue) -> JSONValue {
        guard case .object(var fields) = meta, let chunk = fields["terminal_output_delta"]?["data"]?.stringValue else {
            return meta
        }
        terminalOutput = (terminalOutput ?? "") + chunk
        fields["terminal_output_delta"] = nil
        return .object(fields)
    }
}

extension ToolCallState {
    /// How the command exited, when the agent says: codex-acp 2.2.2 puts it in
    /// `_meta.terminal_exit.exit_code` for a command it ran in a terminal and in
    /// `rawOutput.exit_code` for one it reports as a read or search.
    public var exitCode: Int? {
        let value = meta?["terminal_exit"]?["exit_code"] ?? rawOutput?["exit_code"]
        guard case .number(let number)? = value else { return nil }
        return Int(exactly: number)
    }
}

extension ToolCallState {
    /// A command that failed with a negative exit code never exited on its own: codex-acp 2.2.2 reports
    /// -1 for a process a signal ended, which is what happens to a command still running when the
    /// agent goes away (a reload replays it as failed, exit code -1; captured 2026-10-20).
    var wasKilled: Bool {
        status == .failed && (exitCode ?? 0) < 0
    }
}
