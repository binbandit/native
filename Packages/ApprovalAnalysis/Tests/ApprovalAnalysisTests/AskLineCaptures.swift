/// Existing captured ACP traffic, copied here so ApprovalAnalysis tests do not depend on app tests.
/// Sources remain alongside each capture. No live sessions are required.
enum AskLineCaptures {
    // claude-agent-acp 0.93.0: Packages/ACP/Tests/ACPTests/Wire.swift
    static let claudeWrite =
        #"{"jsonrpc":"2.0","id":0,"method":"session/request_permission","params":{"toolCall":{"toolCallId":"toolu_01BinsUr4xDe5bRwEykrhsx8","name":"Write","status":"pending","rawInput":{"file_path":"/private/tmp/acp-research/sandbox/out.txt","content":"done\n"},"title":"Write /private/tmp/acp-research/sandbox/out.txt","kind":"edit","content":[{"type":"diff","path":"/private/tmp/acp-research/sandbox/out.txt","oldText":null,"newText":"done\n"}],"locations":[{"path":"/private/tmp/acp-research/sandbox/out.txt"}]},"options":[{"optionId":"allow-once","name":"Yes","kind":"allow_once"},{"optionId":"allow-with-updates","name":"Yes, allow all edits in sandbox/ during this session","kind":"allow_always"},{"optionId":"reject","name":"No","kind":"reject_once"}],"sessionId":"59be18cd-5e67-47b1-8562-9996457a07e9"}}"#
    // codex-acp 2.2.2: Packages/ACP/Tests/ACPTests/ShellCommandTests.swift
    static let codexCommand =
        #"{"jsonrpc":"2.0","id":0,"method":"session/request_permission","params":{"sessionId":"01a14e07-45f8-7383-8217-ac2e86f10e8b","toolCall":{"toolCallId":"exec-1dbcba42-836a-46da-8c16-9fa44fca8e48","title":"Run command","rawInput":{"command":"\"printf 'ship\\\\n' > todo.txt\"","cwd":"/tmp/companion2-work/sandbox"},"kind":"execute","status":"pending"},"options":[{"optionId":"allow_once","name":"Yes, proceed","kind":"allow_once"},{"optionId":"accept_execpolicy_amendment","name":"Yes, and don't ask again for commands that start with `printf 'ship\\n' > todo.txt`","kind":"allow_always"},{"optionId":"cancel","name":"No, and tell Codex what to do differently","kind":"reject_once"}]}}"#
    // codex-acp 2.2.2: Packages/ACP/Tests/ACPTests/MCPToolCallTests.swift
    static let codexMCP =
        #"{"jsonrpc":"2.0","method":"session/update","params":{"sessionId":"01a14e13-0751-70b1-90d9-eb18ee6b63e9","update":{"sessionUpdate":"tool_call","toolCallId":"call_mcp_1","kind":"execute","title":"mcp.native.setup_status","status":"in_progress","rawInput":{"server":"native","tool":"setup_status","arguments":{"verbose":true}},"_meta":{"is_mcp_tool_call":true}}}}"#
    // claude-agent-acp 0.93: native/Views/Transcript/TranscriptFixtures.swift
    static let claudeQuestionStart =
        #"{"_meta":{"claudeCode":{"toolName":"AskUserQuestion"}},"toolCallId":"toolu_016PGc48eyfVKaczjHf1iguq","name":"AskUserQuestion","rawInput":{},"status":"pending","title":"Asking for your input","kind":"other","content":[]}"#
    static let claudeQuestion =
        #"{"_meta":{"claudeCode":{"toolName":"AskUserQuestion"}},"toolCallId":"toolu_016PGc48eyfVKaczjHf1iguq","rawInput":{"questions":[{"question":"Which color do you prefer?","header":"Color","multiSelect":false,"options":[{"label":"Red","description":"A warm, bold color"},{"label":"Blue","description":"A cool, calm color"}]},{"question":"Which sizes should ship?","header":"Sizes","multiSelect":true,"options":[{"label":"Small","description":"For phones"},{"label":"Large","description":"For desktops"}]}]},"title":"Which color do you prefer?"}"#
}
