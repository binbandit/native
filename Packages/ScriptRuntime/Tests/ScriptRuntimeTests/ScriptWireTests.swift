import Foundation
import Testing

@testable import ScriptRuntime

/// Frames, lines and declarations, checked against what the runtime really sends.
@Suite struct ScriptWireTests {
    /// Captured from `native-script-runtime` running a script that calls one tool and prints twice.
    static let captured = """
        {"type":"ready","protocolVersion":2}
        {"type":"evaluation_started"}
        {"type":"tool_call","id":1,"toolName":"add","input":{"a":1,"b":2}}
        {"type":"text","text":"sum 3","end":true}
        {"type":"text","text":"{\\"ok\\":true} [1,2]","end":true}
        {"type":"result"}
        {"type":"error","error":{"kind":"exception","message":"TypeError: boom","line":2,"column":8}}
        {"type":"error","error":{"kind":"internal","message":"A runtime runs one script"}}
        {"type":"error","error":{"kind":"from_the_future","message":"?"}}

        """

    @Test func decodesCapturedFrames() throws {
        var splitter = ScriptLineSplitter()
        let lines = try splitter.append(Data(Self.captured.utf8))
        let frames = try lines.map { try JSONDecoder().decode(ScriptOutboundFrame.self, from: $0) }
        #expect(
            frames == [
                .ready(protocolVersion: 2),
                .evaluationStarted,
                .toolCall(id: 1, toolName: "add", input: ["a": 1, "b": 2]),
                .text("sum 3", end: true),
                .text(#"{"ok":true} [1,2]"#, end: true),
                .result,
                .error(ScriptFailure(kind: .exception, message: "TypeError: boom", line: 2, column: 8)),
                .error(ScriptFailure(kind: .runtime, message: "A runtime runs one script")),
                .error(ScriptFailure(kind: .unknown, message: "?")),
            ])
        #expect(!splitter.hasPartialLine)
    }

    @Test func encodesInboundFrames() throws {
        let evaluate = ScriptInboundFrame.evaluate(
            code: "text(1)", bindings: [.init(path: ["a", "b"], toolName: "a.b")], inputs: ["x": "y"])
        let line = String(decoding: try evaluate.line(), as: UTF8.self)
        #expect(line.hasSuffix("\n"))
        let object = try JSONDecoder().decode(ScriptJSON.self, from: Data(line.utf8))
        #expect(
            object == [
                "type": "evaluate", "code": "text(1)", "bindings": [["path": ["a", "b"], "toolName": "a.b"]],
                "inputs": ["x": "y"],
            ])
        let result = try ScriptInboundFrame.toolResult(id: 7, isError: true, content: "nope").line()
        #expect(
            try JSONDecoder().decode(ScriptJSON.self, from: result) == [
                "type": "tool_result", "id": 7, "isError": true, "content": "nope",
            ])
    }

    @Test func splitsLinesAcrossChunksAndRefusesHugeOnes() throws {
        var splitter = ScriptLineSplitter(maxLine: 8)
        #expect(try splitter.append(Data("ab".utf8)).isEmpty)
        #expect(try splitter.append(Data("c\nde\nf".utf8)) == [Data("abc".utf8), Data("de".utf8)])
        #expect(splitter.hasPartialLine)
        #expect(throws: ScriptLineSplitter.LineTooLong.self) { try splitter.append(Data("123456789".utf8)) }
    }

    @Test func rendersDeclarationsForModels() {
        let getTask = ScriptBinding(
            path: ["get_task"],
            summary: "Check a task's status and its latest reply without waiting. Works on any session.",
            inputSchema: ["type": "object", "properties": ["task_id": ["type": "string"]], "required": ["task_id"]],
            outputSchema: [
                "type": "object",
                "properties": [
                    "task_id": ["type": "string"],
                    "status": ["type": "string", "enum": ["running", "idle"]],
                    "tags": ["type": "array", "items": ["type": "string"]],
                ],
                "required": ["task_id", "status"],
            ]
        ) { _ in nil }
        let listAgents = ScriptBinding(path: ["list_agents"], inputSchema: ["type": "object", "properties": [:]]) { _ in
            nil
        }
        #expect(
            ScriptReference.declarations(for: [getTask, listAgents]) == """
                // Check a task's status and its latest reply without waiting.
                tools.get_task(input: { task_id: string }): Promise<{ status: "running" | "idle"; tags?: string[]; task_id: string }>
                tools.list_agents(): Promise<unknown>
                """)
    }

    @Test func reportsResultsForModels() {
        let failed = ScriptRunResult(
            output: ["2 tasks"], toolCalls: [],
            failure: ScriptFailure(kind: .syntax, message: "SyntaxError: Unexpected token ';'", line: 2, column: 11),
            duration: .zero)
        #expect(
            failed.report == "2 tasks\n\nScript didn't compile at line 2, column 11: SyntaxError: Unexpected token ';'")
        let silent = ScriptRunResult(output: [], toolCalls: [], failure: nil, duration: .zero)
        #expect(silent.report.contains("without output"))
        #expect(failed.summary["failure"]?["line"] == 2)
    }
}
