// Captured from codex-acp 2.2.2 with Codex Luna, low effort, and a test-only auto-compaction
// threshold of 1,000 tokens. Only session and compaction identifiers have been replaced.
extension Wire {
    static let codexAutomaticCompaction = [
        #"{"jsonrpc":"2.0","method":"session/update","params":{"sessionId":"fixture","update":{"sessionUpdate":"usage_update","used":19289,"size":258400}}}"#,
        #"{"jsonrpc":"2.0","method":"session/update","params":{"sessionId":"fixture","update":{"sessionUpdate":"compaction_update","compactionId":"compact-1","status":"in_progress"}}}"#,
        #"{"jsonrpc":"2.0","method":"session/update","params":{"sessionId":"fixture","update":{"sessionUpdate":"usage_update","used":22402,"size":258400}}}"#,
        #"{"jsonrpc":"2.0","method":"session/update","params":{"sessionId":"fixture","update":{"sessionUpdate":"compaction_update","compactionId":"compact-1","status":"completed"}}}"#,
        #"{"jsonrpc":"2.0","method":"session/update","params":{"sessionId":"fixture","update":{"sessionUpdate":"usage_update","used":19339,"size":258400}}}"#,
    ]
}
