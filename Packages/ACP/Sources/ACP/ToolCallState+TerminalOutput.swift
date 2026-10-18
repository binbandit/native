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
