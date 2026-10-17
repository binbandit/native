import Foundation
import ACP

/// Real traffic captured from `@agentclientprotocol/claude-agent-acp` 0.93.0 driving Claude Code: one
/// session and one prompt that reads a file, writes one (behind a permission prompt) and runs `ls`.
/// Lines are verbatim apart from a shortened model list.
enum Wire {
    static let sessionID = SessionID("59be18cd-5e67-47b1-8562-9996457a07e9")
    static let readToolCallID = "toolu_01WkiCvJFuuXn23oETFc9Qsh"
    static let writeToolCallID = "toolu_01BinsUr4xDe5bRwEykrhsx8"
    static let bashToolCallID = "toolu_01Dd4VbADwYwVHsKaZ2geoHP"

    // MARK: - Setup

    /// From a later capture, once clients advertised the `subagents` capability.
    static let initializeRequest = #"{"jsonrpc":"2.0","id":0,"method":"initialize","params":{"protocolVersion":1,"clientCapabilities":{"subagents":{}},"clientInfo":{"name":"probe","version":"0"}}}"#

    /// The `result` of the initialize response.
    static let initializeResult = #"{"protocolVersion":1,"agentCapabilities":{"_meta":{"claudeCode":{"promptQueueing":true},"authStatus":{}},"promptCapabilities":{"image":true,"embeddedContext":true},"mcpCapabilities":{"http":true,"sse":true},"auth":{"logout":{}},"providers":{},"loadSession":true,"sessionCapabilities":{"additionalDirectories":{},"close":{},"delete":{},"fork":{},"list":{},"resume":{},"systemPrompt":{"mode":{"override":{}}}}},"agentInfo":{"name":"@agentclientprotocol/claude-agent-acp","title":"Claude Agent","version":"0.93.0"},"authMethods":[],"_meta":{"steering":{"supported":true}}}"#

    /// The `result` of the session/new response, with the model list cut from 66 entries to 3.
    static let newSessionResult = #"""
    {
      "sessionId": "59be18cd-5e67-47b1-8562-9996457a07e9",
      "modes": {"currentModeId":"auto","availableModes":[{"id":"default","name":"Manual","description":"Always ask before making changes"},{"id":"acceptEdits","name":"Accept edits","description":"Automatically accept all file edits"},{"id":"plan","name":"Plan","description":"Create a plan before making changes"},{"id":"auto","name":"Auto","description":"Claude handles permission decisions"},{"id":"bypassPermissions","name":"Bypass permissions","description":"Accepts all permissions"}]},
      "configOptions": [
        {"id":"mode","name":"Mode","description":"Session permission mode","category":"mode","type":"select","currentValue":"auto","options":[
          {"value":"default","name":"Manual","description":"Always ask before making changes"},
          {"value":"acceptEdits","name":"Accept edits","description":"Automatically accept all file edits"},
          {"value":"plan","name":"Plan","description":"Create a plan before making changes"},
          {"value":"auto","name":"Auto","description":"Claude handles permission decisions"},
          {"value":"bypassPermissions","name":"Bypass permissions","description":"Accepts all permissions"}
        ]},
        {"id":"model","name":"Model","description":"AI model to use","category":"model","type":"select","currentValue":"opus","options":[
          {"value":"default","name":"Default (recommended)","description":"Opus"},
          {"value":"opus","name":"Opus 5.5","description":"Opus 5.5 · Best for everyday, complex tasks · $4/$20 per Mtok"},
          {"value":"claude-fable-5","name":"Claude Fable 5","description":"From gateway"}
        ]},
        {"id":"effort","name":"Effort","description":"Available effort levels for this model","category":"thought_level","type":"select","currentValue":"xhigh","options":[
          {"value":"default","name":"Default"},{"value":"low","name":"Low"},{"value":"medium","name":"Medium"},{"value":"high","name":"High"},{"value":"xhigh","name":"Xhigh"},{"value":"max","name":"Max"}
        ]},
        {"id":"fast","name":"Fast mode","description":"Faster responses on supported models","category":"model_config","type":"select","currentValue":"off","options":[
          {"value":"on","name":"On"},{"value":"off","name":"Off"}
        ]}
      ]
    }
    """#

    /// An extension notification the adapter sends during session/new (from the later capture).
    static let authStatusNotification = #"{"jsonrpc":"2.0","method":"_auth/status_update","params":{"authStatus":{"kind":"none","label":"Not logged in"}}}"#

    /// Sent after `session/set_mode` to `default`; only the mode option is kept.
    static let configOptionUpdate = #"{"jsonrpc":"2.0","method":"session/update","params":{"sessionId":"59be18cd-5e67-47b1-8562-9996457a07e9","update":{"sessionUpdate":"config_option_update","configOptions":[{"id":"mode","name":"Mode","description":"Session permission mode","category":"mode","type":"select","currentValue":"default","options":[{"value":"default","name":"Manual","description":"Always ask before making changes"},{"value":"acceptEdits","name":"Accept edits","description":"Automatically accept all file edits"},{"value":"plan","name":"Plan","description":"Create a plan before making changes"},{"value":"auto","name":"Auto","description":"Claude handles permission decisions"},{"value":"bypassPermissions","name":"Bypass permissions","description":"Accepts all permissions"}]}]}}}"#

    // MARK: - The prompt turn

    static let promptText = "Read notes.txt, then create a file named out.txt containing the word done, then run 'ls' with bash. Keep replies very short."

    static let promptRequest = #"{"jsonrpc":"2.0","id":3,"method":"session/prompt","params":{"sessionId":"59be18cd-5e67-47b1-8562-9996457a07e9","prompt":[{"type":"text","text":"Read notes.txt, then create a file named out.txt containing the word done, then run 'ls' with bash. Keep replies very short."}]}}"#

    static let usageWithoutCost = #"{"jsonrpc":"2.0","method":"session/update","params":{"sessionId":"59be18cd-5e67-47b1-8562-9996457a07e9","update":{"sessionUpdate":"usage_update","used":234117,"size":1000000,"_meta":{"_claude/model":"claude-opus-5-5"}}}}"#

    static let readToolCall = #"{"jsonrpc":"2.0","method":"session/update","params":{"sessionId":"59be18cd-5e67-47b1-8562-9996457a07e9","update":{"_meta":{"claudeCode":{"toolName":"Read"}},"toolCallId":"toolu_01WkiCvJFuuXn23oETFc9Qsh","sessionUpdate":"tool_call","name":"Read","rawInput":{},"status":"pending","title":"Read File","kind":"read","content":[],"locations":[]}}}"#

    static let readInputUpdate = #"{"jsonrpc":"2.0","method":"session/update","params":{"sessionId":"59be18cd-5e67-47b1-8562-9996457a07e9","update":{"_meta":{"claudeCode":{"toolName":"Read"}},"toolCallId":"toolu_01WkiCvJFuuXn23oETFc9Qsh","sessionUpdate":"tool_call_update","rawInput":{"file_path":"/private/tmp/acp-research/sandbox/notes.txt"},"title":"Read /private/tmp/acp-research/sandbox/notes.txt","locations":[{"path":"/private/tmp/acp-research/sandbox/notes.txt","line":1}]}}}"#

    /// Carries nothing but adapter `_meta`.
    static let readMetaOnlyUpdate = #"{"jsonrpc":"2.0","method":"session/update","params":{"sessionId":"59be18cd-5e67-47b1-8562-9996457a07e9","update":{"_meta":{"claudeCode":{"toolResponse":{"type":"text","file":{"filePath":"/private/tmp/acp-research/sandbox/notes.txt","content":"hello\n","numLines":2,"startLine":1,"totalLines":2}},"toolName":"Read"}},"toolCallId":"toolu_01WkiCvJFuuXn23oETFc9Qsh","sessionUpdate":"tool_call_update"}}}"#

    static let readCompletedUpdate = #"{"jsonrpc":"2.0","method":"session/update","params":{"sessionId":"59be18cd-5e67-47b1-8562-9996457a07e9","update":{"_meta":{"claudeCode":{"toolName":"Read"}},"toolCallId":"toolu_01WkiCvJFuuXn23oETFc9Qsh","sessionUpdate":"tool_call_update","status":"completed","rawOutput":"1\thello\n2\t","content":[{"type":"content","content":{"type":"text","text":"```\n1\thello\n```"}}]}}}"#

    static let writeToolCall = #"{"jsonrpc":"2.0","method":"session/update","params":{"sessionId":"59be18cd-5e67-47b1-8562-9996457a07e9","update":{"_meta":{"claudeCode":{"toolName":"Write"}},"toolCallId":"toolu_01BinsUr4xDe5bRwEykrhsx8","sessionUpdate":"tool_call","name":"Write","rawInput":{},"status":"pending","title":"Preparing file…","kind":"edit","content":[],"locations":[]}}}"#

    static let writeDiffUpdate = #"{"jsonrpc":"2.0","method":"session/update","params":{"sessionId":"59be18cd-5e67-47b1-8562-9996457a07e9","update":{"_meta":{"claudeCode":{"toolName":"Write"}},"toolCallId":"toolu_01BinsUr4xDe5bRwEykrhsx8","sessionUpdate":"tool_call_update","rawInput":{"file_path":"/private/tmp/acp-research/sandbox/out.txt","content":"done\n"},"content":[{"type":"diff","path":"/private/tmp/acp-research/sandbox/out.txt","oldText":null,"newText":"done\n"}]}}}"#

    static let bashToolCall = #"{"jsonrpc":"2.0","method":"session/update","params":{"sessionId":"59be18cd-5e67-47b1-8562-9996457a07e9","update":{"_meta":{"claudeCode":{"toolName":"Bash"}},"toolCallId":"toolu_01Dd4VbADwYwVHsKaZ2geoHP","sessionUpdate":"tool_call","name":"Bash","rawInput":{},"status":"pending","title":"Terminal","kind":"execute","content":[]}}}"#

    /// An agent-to-client request, with the agent's own id.
    static let permissionRequest = #"{"jsonrpc":"2.0","id":0,"method":"session/request_permission","params":{"toolCall":{"toolCallId":"toolu_01BinsUr4xDe5bRwEykrhsx8","name":"Write","status":"pending","rawInput":{"file_path":"/private/tmp/acp-research/sandbox/out.txt","content":"done\n"},"title":"Write /private/tmp/acp-research/sandbox/out.txt","kind":"edit","content":[{"type":"diff","path":"/private/tmp/acp-research/sandbox/out.txt","oldText":null,"newText":"done\n"}],"locations":[{"path":"/private/tmp/acp-research/sandbox/out.txt"}]},"options":[{"optionId":"allow-once","name":"Yes","kind":"allow_once"},{"optionId":"allow-with-updates","name":"Yes, allow all edits in sandbox/ during this session","kind":"allow_always"},{"optionId":"reject","name":"No","kind":"reject_once"}],"sessionId":"59be18cd-5e67-47b1-8562-9996457a07e9"}}"#

    /// The client's answer to `permissionRequest`.
    static let permissionResponse = #"{"jsonrpc":"2.0","id":0,"result":{"outcome":{"outcome":"selected","optionId":"allow-once"}}}"#

    static let agentMessageChunks = [
        #"{"jsonrpc":"2.0","method":"session/update","params":{"sessionId":"59be18cd-5e67-47b1-8562-9996457a07e9","update":{"sessionUpdate":"agent_message_chunk","content":{"type":"text","text":"All three done. `notes."},"messageId":"msg_011Cg7aw33VUg8MYQNHDB4UE"}}}"#,
        #"{"jsonrpc":"2.0","method":"session/update","params":{"sessionId":"59be18cd-5e67-47b1-8562-9996457a07e9","update":{"sessionUpdate":"agent_message_chunk","content":{"type":"text","text":"txt` cont"},"messageId":"msg_011Cg7aw33VUg8MYQNHDB4UE"}}}"#,
        #"{"jsonrpc":"2.0","method":"session/update","params":{"sessionId":"59be18cd-5e67-47b1-8562-9996457a07e9","update":{"sessionUpdate":"agent_message_chunk","content":{"type":"text","text":"ains \"hello\", `out."},"messageId":"msg_011Cg7aw33VUg8MYQNHDB4UE"}}}"#,
        #"{"jsonrpc":"2.0","method":"session/update","params":{"sessionId":"59be18cd-5e67-47b1-8562-9996457a07e9","update":{"sessionUpdate":"agent_message_chunk","content":{"type":"text","text":"txt` now cont"},"messageId":"msg_011Cg7aw33VUg8MYQNHDB4UE"}}}"#,
        #"{"jsonrpc":"2.0","method":"session/update","params":{"sessionId":"59be18cd-5e67-47b1-8562-9996457a07e9","update":{"sessionUpdate":"agent_message_chunk","content":{"type":"text","text":"ains \"done\", and `ls"},"messageId":"msg_011Cg7aw33VUg8MYQNHDB4UE"}}}"#,
        #"{"jsonrpc":"2.0","method":"session/update","params":{"sessionId":"59be18cd-5e67-47b1-8562-9996457a07e9","update":{"sessionUpdate":"agent_message_chunk","content":{"type":"text","text":"` shows `notes.tx"},"messageId":"msg_011Cg7aw33VUg8MYQNHDB4UE"}}}"#,
        #"{"jsonrpc":"2.0","method":"session/update","params":{"sessionId":"59be18cd-5e67-47b1-8562-9996457a07e9","update":{"sessionUpdate":"agent_message_chunk","content":{"type":"text","text":"t` and `out.txt"},"messageId":"msg_011Cg7aw33VUg8MYQNHDB4UE"}}}"#,
        #"{"jsonrpc":"2.0","method":"session/update","params":{"sessionId":"59be18cd-5e67-47b1-8562-9996457a07e9","update":{"sessionUpdate":"agent_message_chunk","content":{"type":"text","text":"`."},"messageId":"msg_011Cg7aw33VUg8MYQNHDB4UE"}}}"#,
    ]

    /// What `agentMessageChunks` add up to.
    static let agentMessage = #"All three done. `notes.txt` contains "hello", `out.txt` now contains "done", and `ls` shows `notes.txt` and `out.txt`."#
    static let agentMessageID = "msg_011Cg7aw33VUg8MYQNHDB4UE"

    static let usageWithCost = #"{"jsonrpc":"2.0","method":"session/update","params":{"sessionId":"59be18cd-5e67-47b1-8562-9996457a07e9","update":{"sessionUpdate":"usage_update","used":234506,"size":1000000,"cost":{"amount":0.19107000000000002,"currency":"USD"},"_meta":{"_claude/origin":{"kind":"human"},"_claude/model":"claude-opus-5-5"}}}}"#

    /// Everything the agent sent between the prompt request and its response, in order.
    static let promptTurn = [
        usageWithoutCost,
        readToolCall,
        readInputUpdate,
        #"{"jsonrpc":"2.0","method":"session/update","params":{"sessionId":"59be18cd-5e67-47b1-8562-9996457a07e9","update":{"sessionUpdate":"usage_update","used":234170,"size":1000000,"_meta":{"_claude/model":"claude-opus-5-5"}}}}"#,
        readMetaOnlyUpdate,
        readCompletedUpdate,
        #"{"jsonrpc":"2.0","method":"session/update","params":{"sessionId":"59be18cd-5e67-47b1-8562-9996457a07e9","update":{"sessionUpdate":"usage_update","used":234198,"size":1000000,"_meta":{"_claude/model":"claude-opus-5-5"}}}}"#,
        writeToolCall,
        #"{"jsonrpc":"2.0","method":"session/update","params":{"sessionId":"59be18cd-5e67-47b1-8562-9996457a07e9","update":{"_meta":{"claudeCode":{"toolName":"Write"}},"toolCallId":"toolu_01BinsUr4xDe5bRwEykrhsx8","sessionUpdate":"tool_call_update","rawInput":{"file_path":"/private/tmp/acp-research/sandbox/out.txt"},"title":"Write /private/tmp/acp-research/sandbox/out.txt","locations":[{"path":"/private/tmp/acp-research/sandbox/out.txt"}]}}}"#,
        writeDiffUpdate,
        bashToolCall,
        permissionRequest,
        #"{"jsonrpc":"2.0","method":"session/update","params":{"sessionId":"59be18cd-5e67-47b1-8562-9996457a07e9","update":{"_meta":{"claudeCode":{"toolResponse":{"type":"create","filePath":"/private/tmp/acp-research/sandbox/out.txt","content":"done\n","structuredPatch":[],"originalFile":null,"userModified":false},"toolName":"Write"}},"toolCallId":"toolu_01BinsUr4xDe5bRwEykrhsx8","sessionUpdate":"tool_call_update"}}}"#,
        #"{"jsonrpc":"2.0","method":"session/update","params":{"sessionId":"59be18cd-5e67-47b1-8562-9996457a07e9","update":{"_meta":{"claudeCode":{"toolName":"Write"}},"toolCallId":"toolu_01BinsUr4xDe5bRwEykrhsx8","sessionUpdate":"tool_call_update","status":"completed","rawOutput":"File created successfully at: /private/tmp/acp-research/sandbox/out.txt (file state is current in your context — no need to Read it back)"}}}"#,
        #"{"jsonrpc":"2.0","method":"session/update","params":{"sessionId":"59be18cd-5e67-47b1-8562-9996457a07e9","update":{"_meta":{"claudeCode":{"toolName":"Bash"}},"toolCallId":"toolu_01Dd4VbADwYwVHsKaZ2geoHP","sessionUpdate":"tool_call_update","rawInput":{"command":"ls"},"title":"ls"}}}"#,
        #"{"jsonrpc":"2.0","method":"session/update","params":{"sessionId":"59be18cd-5e67-47b1-8562-9996457a07e9","update":{"_meta":{"claudeCode":{"toolName":"Bash"}},"toolCallId":"toolu_01Dd4VbADwYwVHsKaZ2geoHP","sessionUpdate":"tool_call_update","rawInput":{"command":"ls","description":"List files in current directory"},"content":[{"type":"content","content":{"type":"text","text":"List files in current directory"}}]}}}"#,
        #"{"jsonrpc":"2.0","method":"session/update","params":{"sessionId":"59be18cd-5e67-47b1-8562-9996457a07e9","update":{"sessionUpdate":"usage_update","used":234343,"size":1000000,"_meta":{"_claude/model":"claude-opus-5-5"}}}}"#,
        #"{"jsonrpc":"2.0","method":"session/update","params":{"sessionId":"59be18cd-5e67-47b1-8562-9996457a07e9","update":{"_meta":{"claudeCode":{"toolResponse":{"stdout":"notes.txt\nout.txt","stderr":"","interrupted":false,"isImage":false,"noOutputExpected":false},"toolName":"Bash"}},"toolCallId":"toolu_01Dd4VbADwYwVHsKaZ2geoHP","sessionUpdate":"tool_call_update"}}}"#,
        #"{"jsonrpc":"2.0","method":"session/update","params":{"sessionId":"59be18cd-5e67-47b1-8562-9996457a07e9","update":{"_meta":{"claudeCode":{"toolName":"Bash"}},"toolCallId":"toolu_01Dd4VbADwYwVHsKaZ2geoHP","sessionUpdate":"tool_call_update","status":"completed","rawOutput":"notes.txt\nout.txt","content":[{"type":"content","content":{"type":"text","text":"```console\nnotes.txt\nout.txt\n```"}}]}}}"#,
        #"{"jsonrpc":"2.0","method":"session/update","params":{"sessionId":"59be18cd-5e67-47b1-8562-9996457a07e9","update":{"sessionUpdate":"usage_update","used":234506,"size":1000000,"_meta":{"_claude/model":"claude-opus-5-5"}}}}"#,
    ] + agentMessageChunks + [
        usageWithCost,
    ]

    /// The `result` of the prompt response.
    static let promptResult = #"{"stopReason":"end_turn","usage":{"inputTokens":6,"outputTokens":283,"cachedReadTokens":694485,"cachedWriteTokens":8245,"totalTokens":703019},"_meta":{"quota":{"token_count":{"totalTokens":703019,"inputTokens":6,"cachedInputTokens":694485,"cachedWriteTokens":8245,"outputTokens":283,"reasoningOutputTokens":0},"model_usage":[{"model":"claude-opus-5-5","token_count":{"totalTokens":704247,"inputTokens":1212,"cachedInputTokens":694485,"cachedWriteTokens":8245,"outputTokens":305,"reasoningOutputTokens":0}}]}}}"#

    // MARK: - Decoding

    static func decode<T: Decodable>(_ type: T.Type, from json: String) throws -> T {
        try JSONDecoder().decode(type, from: Data(json.utf8))
    }

    /// The `params` of a request or notification line.
    static func params<T: Decodable>(_ type: T.Type, of line: String) throws -> T {
        try decode(Params<T>.self, from: line).params
    }

    /// The update carried by a `session/update` line.
    static func update(_ line: String) throws -> SessionUpdate {
        try params(SessionNotification.self, of: line).update
    }

    /// Routes an agent line the way `ACPConnection` hands it to its event handler.
    static func event(_ line: String) throws -> AgentEvent {
        let envelope = try decode(Envelope.self, from: line)
        switch (envelope.method, envelope.id) {
        case ("session/update", nil):
            return .sessionUpdate(try params(SessionNotification.self, of: line))
        case ("session/request_permission", let id?):
            return .permissionRequest(id, try params(RequestPermissionRequest.self, of: line))
        default:
            throw UnroutableLine(line: line)
        }
    }

    static func json(_ string: String) throws -> JSONValue {
        try decode(JSONValue.self, from: string)
    }

    static func json(encoding value: some Encodable) throws -> JSONValue {
        try JSONDecoder().decode(JSONValue.self, from: JSONEncoder().encode(value))
    }

    private struct Envelope: Decodable {
        var id: RequestID?
        var method: String?
    }

    private struct Params<T: Decodable>: Decodable {
        var params: T
    }

    struct UnroutableLine: Error {
        var line: String
    }
}
