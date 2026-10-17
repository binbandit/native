import Foundation
import Testing
@testable import ACP

struct SchemaDecodingTests {
    @Test func initializeResponseReportsCapabilities() throws {
        let response = try Wire.decode(InitializeResponse.self, from: Wire.initializeResult)

        #expect(response.protocolVersion == 1)
        #expect(response.agentCapabilities.loadSession)
        #expect(response.agentCapabilities.image)
        // Advertised by an empty `sessionCapabilities.list` object.
        #expect(response.agentCapabilities.listSessions)
        #expect(response.agentInfo == Implementation(name: "@agentclientprotocol/claude-agent-acp", title: "Claude Agent", version: "0.93.0"))
        #expect(response.authMethods.isEmpty)
    }

    @Test func newSessionResponseCarriesSelectConfigOptions() throws {
        let response = try Wire.decode(NewSessionResponse.self, from: Wire.newSessionResult)
        let options = try #require(response.configOptions)

        #expect(response.sessionId == Wire.sessionID)
        #expect(options.map(\.id) == ["mode", "model", "effort", "fast"])
        #expect(options.map(\.category) == ["mode", "model", "thought_level", "model_config"])

        let mode = try #require(selection(options[0]))
        #expect(mode.current == "auto")
        #expect(mode.values == ["default", "acceptEdits", "plan", "auto", "bypassPermissions"])
        let model = try #require(selection(options[1]))
        #expect(model.current == "opus")
        #expect(model.values == ["default", "opus", "claude-fable-5"])
    }

    @Test func configOptionUpdateCarriesTheNewValue() throws {
        guard case .configOptions(let options) = try Wire.update(Wire.configOptionUpdate) else {
            Issue.record("Expected config options")
            return
        }
        #expect(options.map(\.id) == ["mode"])
        #expect(selection(options[0])?.current == "default")
    }

    @Test func groupedSelectOptionsFlatten() throws {
        // ACP's grouped form of `options`; the adapter sends flat lists, other agents may not.
        let json = #"""
        {"id":"model","name":"Model","category":"model","type":"select","currentValue":"opus","options":[
          {"group":"anthropic","name":"Anthropic","options":[{"value":"default","name":"Default (recommended)","description":"Opus"},{"value":"opus","name":"Opus 5.5"}]},
          {"group":"gateway","name":"From gateway","options":[{"value":"claude-fable-5","name":"Claude Fable 5"}]}
        ]}
        """#
        let option = try Wire.decode(ConfigOption.self, from: json)

        #expect(option.kind == .select(currentValue: "opus", options: [
            ConfigOption.SelectOption(value: "default", name: "Default (recommended)", description: "Opus"),
            ConfigOption.SelectOption(value: "opus", name: "Opus 5.5"),
            ConfigOption.SelectOption(value: "claude-fable-5", name: "Claude Fable 5"),
        ]))
    }

    @Test func toolCallSequenceDecodes() throws {
        let updates = try [Wire.readToolCall, Wire.readInputUpdate, Wire.readMetaOnlyUpdate, Wire.readCompletedUpdate].map(Wire.update)
        guard case .toolCall(let created) = updates[0],
              case .toolCallUpdate(let described) = updates[1],
              case .toolCallUpdate(let metaOnly) = updates[2],
              case .toolCallUpdate(let completed) = updates[3]
        else {
            Issue.record("Expected a tool_call followed by three tool_call_updates, got \(updates)")
            return
        }

        var expectedCreated = ToolCallUpdate(toolCallId: Wire.readToolCallID, title: "Read File", kind: .read, status: .pending)
        expectedCreated.name = "Read"
        expectedCreated.rawInput = .object([:])
        expectedCreated.content = []
        expectedCreated.locations = []
        #expect(created == expectedCreated)

        // Updates carry only what changed; everything else stays nil.
        var expectedDescribed = ToolCallUpdate(toolCallId: Wire.readToolCallID, title: "Read /private/tmp/acp-research/sandbox/notes.txt")
        expectedDescribed.rawInput = .object(["file_path": .string("/private/tmp/acp-research/sandbox/notes.txt")])
        expectedDescribed.locations = [ToolCallLocation(path: "/private/tmp/acp-research/sandbox/notes.txt", line: 1)]
        #expect(described == expectedDescribed)

        #expect(metaOnly == ToolCallUpdate(toolCallId: Wire.readToolCallID))

        var expectedCompleted = ToolCallUpdate(toolCallId: Wire.readToolCallID, status: .completed)
        expectedCompleted.rawOutput = .string("1\thello\n2\t")
        expectedCompleted.content = [.content(.text("```\n1\thello\n```"))]
        #expect(completed == expectedCompleted)
    }

    @Test func diffForANewFileHasNoOldText() throws {
        guard case .toolCallUpdate(let update) = try Wire.update(Wire.writeDiffUpdate) else {
            Issue.record("Expected a tool_call_update")
            return
        }
        #expect(update.content == [.diff(FileDiff(path: "/private/tmp/acp-research/sandbox/out.txt", oldText: nil, newText: "done\n"))])
    }

    @Test func permissionRequestDecodes() throws {
        let request = try Wire.params(RequestPermissionRequest.self, of: Wire.permissionRequest)

        #expect(request.sessionId == Wire.sessionID)
        #expect(request.toolCall.toolCallId == Wire.writeToolCallID)
        #expect(request.toolCall.title == "Write /private/tmp/acp-research/sandbox/out.txt")
        #expect(request.toolCall.kind == .edit)
        #expect(request.toolCall.status == .pending)
        #expect(request.options == [
            PermissionOption(optionId: "allow-once", name: "Yes", kind: .allowOnce),
            PermissionOption(optionId: "allow-with-updates", name: "Yes, allow all edits in sandbox/ during this session", kind: .allowAlways),
            PermissionOption(optionId: "reject", name: "No", kind: .rejectOnce),
        ])
        #expect(request.options.map(\.isRejection) == [false, false, true])
    }

    @Test func usageUpdateDecodesWithAndWithoutCost() throws {
        guard case .usage(let withCost) = try Wire.update(Wire.usageWithCost),
              case .usage(let withoutCost) = try Wire.update(Wire.usageWithoutCost)
        else {
            Issue.record("Expected usage updates")
            return
        }
        #expect(withCost == Usage(used: 234_506, size: 1_000_000, cost: Usage.Cost(amount: 0.19107000000000002, currency: "USD")))
        #expect(withCost.fractionUsed == 0.234506)
        #expect(withoutCost == Usage(used: 234_117, size: 1_000_000, cost: nil))
    }

    @Test func unknownUpdateKindIsUnsupported() throws {
        let line = #"{"jsonrpc":"2.0","method":"session/update","params":{"sessionId":"59be18cd-5e67-47b1-8562-9996457a07e9","update":{"sessionUpdate":"compaction_update","compactionId":"cmp_1","status":"completed"}}}"#
        guard case .unsupported(let kind) = try Wire.update(line) else {
            Issue.record("Expected an unsupported update")
            return
        }
        #expect(kind == "compaction_update")
    }

    /// Cursor reports the agent switching modes this way instead of with `config_option_update`.
    @Test func currentModeUpdateMovesTheModeOption() throws {
        var state = SessionState()
        state.apply(try Wire.update(Wire.configOptionUpdate))
        state.apply(try Wire.update(#"{"jsonrpc":"2.0","method":"session/update","params":{"sessionId":"59be18cd-5e67-47b1-8562-9996457a07e9","update":{"sessionUpdate":"current_mode_update","currentModeId":"plan"}}}"#))
        guard case .select(let current, _)? = state.configOptions.first(where: { $0.id == "mode" })?.kind else {
            Issue.record("Expected the mode select option")
            return
        }
        #expect(current == "plan")

        // A mode the option doesn't list is ignored rather than leaving the picker on an unknown value.
        state.apply(try Wire.update(#"{"jsonrpc":"2.0","method":"session/update","params":{"sessionId":"59be18cd-5e67-47b1-8562-9996457a07e9","update":{"sessionUpdate":"current_mode_update","currentModeId":"nonexistent"}}}"#))
        guard case .select(let unchanged, _)? = state.configOptions.first(where: { $0.id == "mode" })?.kind else {
            Issue.record("Expected the mode select option")
            return
        }
        #expect(unchanged == "plan")
    }

    /// The adapter formats `updatedAt` with `Date.toISOString()`, which always has milliseconds.
    @Test(arguments: [
        ("2026-10-17T20:38:12.345Z", 1_792_269_492_345),
        ("2026-10-17T20:38:12Z", 1_792_269_492_000),
    ])
    func sessionInfoParsesUpdatedAt(updatedAt: String, millisecondsSince1970: Int) throws {
        // The shape of the adapter's session/list result.
        let json = #"{"sessions":[{"sessionId":"59be18cd-5e67-47b1-8562-9996457a07e9","cwd":"/private/tmp/acp-research/sandbox","title":"Read notes.txt","updatedAt":"\#(updatedAt)"}],"nextCursor":"offset:50"}"#
        let response = try Wire.decode(ListSessionsResponse.self, from: json)
        let date = try #require(response.sessions.first?.updatedDate)

        #expect(Int((date.timeIntervalSince1970 * 1000).rounded()) == millisecondsSince1970)
        #expect(response.nextCursor == "offset:50")
    }

    // MARK: - Encoding

    /// Claude reads the capability at the top level, Cursor under `_meta`.
    @Test func initializeRequestAdvertisesSubagents() throws {
        let request = InitializeRequest(clientInfo: Implementation(name: "probe", version: "0"))
        let expected = try Wire.json(#"{"protocolVersion":1,"clientCapabilities":{"subagents":{},"_meta":{"subagents":{}}},"clientInfo":{"name":"probe","version":"0"}}"#)
        #expect(try Wire.json(encoding: request) == expected)
    }

    @Test func promptRequestEncodesAsOnTheWire() throws {
        let request = PromptRequest(sessionId: Wire.sessionID, prompt: [.text(Wire.promptText)])
        #expect(try Wire.json(encoding: request) == Wire.json(Wire.promptRequest)["params"])
    }

    @Test func permissionResponseEncodesAsOnTheWire() throws {
        #expect(try Wire.json(encoding: RequestPermissionResponse.selected(optionId: "allow-once")) == Wire.json(Wire.permissionResponse)["result"])
        #expect(try Wire.json(encoding: RequestPermissionResponse.cancelled) == Wire.json(#"{"outcome":{"outcome":"cancelled"}}"#))
    }
}

/// A select option's current value and its option values, flattened.
private func selection(_ option: ConfigOption) -> (current: String, values: [String])? {
    guard case .select(let current, let options) = option.kind else { return nil }
    return (current, options.map(\.value))
}
