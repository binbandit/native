@testable import ACP

/// Codex 0.165.0 in code mode (`--enable code_mode --enable code_mode_only`) through codex-acp
/// 2.2.2, on 6.1 Sol: one prompt that runs the tests, lists and searches, reads two files, patches
/// one and runs a slow final check. codex-acp reports each nested tool as its own call. Verbatim
/// apart from the project path.
enum CodexCodeModeWire {
    static let lines = [
        #"{"jsonrpc":"2.0","method":"session/update","params":{"sessionId":"01a18760-e6c1-7790-87ab-e066461b106f","update":{"sessionUpdate":"tool_call","toolCallId":"exec-c7be9e48-da6a-4a50-958c-230823fff573","name":"exec_command","kind":"execute","title":"python3 -m unittest","status":"in_progress","content":[{"type":"terminal","terminalId":"exec-c7be9e48-da6a-4a50-958c-230823fff573"}],"rawInput":{"command":"python3 -m unittest","cwd":"/Users/me/project"},"_meta":{"terminal_info":{"cwd":"/Users/me/project","terminal_id":"exec-c7be9e48-da6a-4a50-958c-230823fff573"}}}}}"#,
        #"{"jsonrpc":"2.0","method":"session/update","params":{"sessionId":"01a18760-e6c1-7790-87ab-e066461b106f","update":{"sessionUpdate":"tool_call_update","toolCallId":"exec-c7be9e48-da6a-4a50-958c-230823fff573","status":"failed","_meta":{"terminal_output_delta":{"data":".F\n======================================================================\nFAIL: test_initials_are_upper_case (test_greet.GreetTests.test_initials_are_upper_case)\n----------------------------------------------------------------------\nTraceback (most recent call last):\n  File \"/Users/me/project/test_greet.py\", line 11, in test_initials_are_upper_case\n    self.assertEqual(initials(\"Grace Brewster Hopper\"), \"GBH\")\nAssertionError: 'gbh' != 'GBH'\n- gbh\n+ GBH\n\n\n----------------------------------------------------------------------\nRan 2 tests in 0.000s\n\nFAILED (failures=1)\n","terminal_id":"exec-c7be9e48-da6a-4a50-958c-230823fff573"},"terminal_exit":{"exit_code":1,"signal":null,"terminal_id":"exec-c7be9e48-da6a-4a50-958c-230823fff573"}}}}}"#,
        #"{"jsonrpc":"2.0","method":"session/update","params":{"sessionId":"01a18760-e6c1-7790-87ab-e066461b106f","update":{"sessionUpdate":"tool_call","toolCallId":"exec-1ac7f4dd-6aa4-4129-ad4b-23197401f4d7","name":"exec_command","kind":"read","title":"List files","status":"in_progress"}}}"#,
        #"{"jsonrpc":"2.0","method":"session/update","params":{"sessionId":"01a18760-e6c1-7790-87ab-e066461b106f","update":{"sessionUpdate":"tool_call_update","toolCallId":"exec-1ac7f4dd-6aa4-4129-ad4b-23197401f4d7","status":"completed","rawOutput":{"exit_code":0},"_meta":{"terminal_output_delta":{"data":"greet.py\ntest_greet.py\n","terminal_id":"exec-1ac7f4dd-6aa4-4129-ad4b-23197401f4d7"}}}}}"#,
        #"{"jsonrpc":"2.0","method":"session/update","params":{"sessionId":"01a18760-e6c1-7790-87ab-e066461b106f","update":{"sessionUpdate":"tool_call","toolCallId":"exec-647719f9-a8a4-48a7-921b-31402ec5069c","name":"exec_command","kind":"search","title":"Search for 'def initials|initials' in .","status":"in_progress"}}}"#,
        #"{"jsonrpc":"2.0","method":"session/update","params":{"sessionId":"01a18760-e6c1-7790-87ab-e066461b106f","update":{"sessionUpdate":"tool_call_update","toolCallId":"exec-647719f9-a8a4-48a7-921b-31402ec5069c","status":"completed","rawOutput":{"exit_code":0},"_meta":{"terminal_output_delta":{"data":"./greet.py:8:def initials(name: str) -> str:\n./test_greet.py:3:from greet import greet, initials\n./test_greet.py:10:    def test_initials_are_upper_case(self):\n./test_greet.py:11:        self.assertEqual(initials(\"Grace Brewster Hopper\"), \"GBH\")\n","terminal_id":"exec-647719f9-a8a4-48a7-921b-31402ec5069c"}}}}}"#,
        #"{"jsonrpc":"2.0","method":"session/update","params":{"sessionId":"01a18760-e6c1-7790-87ab-e066461b106f","update":{"sessionUpdate":"tool_call","toolCallId":"exec-63c9b889-c57d-4daf-b0b4-9b4dce84b608","name":"exec_command","kind":"execute","title":"cat greet.py test_greet.py","status":"in_progress","content":[{"type":"terminal","terminalId":"exec-63c9b889-c57d-4daf-b0b4-9b4dce84b608"}],"rawInput":{"command":"cat greet.py test_greet.py","cwd":"/Users/me/project"},"_meta":{"terminal_info":{"cwd":"/Users/me/project","terminal_id":"exec-63c9b889-c57d-4daf-b0b4-9b4dce84b608"}}}}}"#,
        #"{"jsonrpc":"2.0","method":"session/update","params":{"sessionId":"01a18760-e6c1-7790-87ab-e066461b106f","update":{"sessionUpdate":"tool_call_update","toolCallId":"exec-63c9b889-c57d-4daf-b0b4-9b4dce84b608","status":"completed","_meta":{"terminal_output_delta":{"data":"import sys\n\n\ndef greet(name: str) -> str:\n    return f\"Hello, {name.strip()}!\"\n\n\ndef initials(name: str) -> str:\n    return \"\".join(part[0] for part in name.split()).lower()\n\n\nif __name__ == \"__main__\":\n    print(greet(\" \".join(sys.argv[1:]) or \"world\"))\nimport unittest\n\nfrom greet import greet, initials\n\n\nclass GreetTests(unittest.TestCase):\n    def test_greet_trims(self):\n        self.assertEqual(greet(\"  Ada \"), \"Hello, Ada!\")\n\n    def test_initials_are_upper_case(self):\n        self.assertEqual(initials(\"Grace Brewster Hopper\"), \"GBH\")\n\n\nif __name__ == \"__main__\":\n    unittest.main()\n","terminal_id":"exec-63c9b889-c57d-4daf-b0b4-9b4dce84b608"},"terminal_exit":{"exit_code":0,"signal":null,"terminal_id":"exec-63c9b889-c57d-4daf-b0b4-9b4dce84b608"}}}}}"#,
        #"{"jsonrpc":"2.0","method":"session/update","params":{"sessionId":"01a18760-e6c1-7790-87ab-e066461b106f","update":{"sessionUpdate":"tool_call","toolCallId":"exec-0d5ae936-3821-4b27-9634-2d53baf63b88","kind":"edit","title":"Editing files","status":"in_progress","content":[{"type":"diff","oldText":"def initials(name: str) -> str:\n    return \"\".join(part[0] for part in name.split()).lower()\n\n","newText":"def initials(name: str) -> str:\n    return \"\".join(part[0] for part in name.split()).upper()\n\n","path":"/Users/me/project/greet.py","_meta":{"kind":"update"}}]}}}"#,
        #"{"jsonrpc":"2.0","method":"session/update","params":{"sessionId":"01a18760-e6c1-7790-87ab-e066461b106f","update":{"sessionUpdate":"tool_call_update","toolCallId":"exec-0d5ae936-3821-4b27-9634-2d53baf63b88","status":"completed"}}}"#,
        #"{"jsonrpc":"2.0","method":"session/update","params":{"sessionId":"01a18760-e6c1-7790-87ab-e066461b106f","update":{"sessionUpdate":"tool_call","toolCallId":"exec-9614150a-94ad-4e61-9487-f07432792a6e","name":"exec_command","kind":"execute","title":"sleep 40; python3 -m unittest","status":"in_progress","content":[{"type":"terminal","terminalId":"exec-9614150a-94ad-4e61-9487-f07432792a6e"}],"rawInput":{"command":"sleep 40; python3 -m unittest","cwd":"/Users/me/project"},"_meta":{"terminal_info":{"cwd":"/Users/me/project","terminal_id":"exec-9614150a-94ad-4e61-9487-f07432792a6e"}}}}}"#,
        #"{"jsonrpc":"2.0","method":"session/update","params":{"sessionId":"01a18760-e6c1-7790-87ab-e066461b106f","update":{"sessionUpdate":"tool_call_update","toolCallId":"exec-9614150a-94ad-4e61-9487-f07432792a6e","_meta":{"terminal_output_delta":{"data":"\n\n","terminal_id":"exec-9614150a-94ad-4e61-9487-f07432792a6e"}}}}}"#,
        #"{"jsonrpc":"2.0","method":"session/update","params":{"sessionId":"01a18760-e6c1-7790-87ab-e066461b106f","update":{"sessionUpdate":"tool_call_update","toolCallId":"exec-9614150a-94ad-4e61-9487-f07432792a6e","_meta":{"terminal_output_delta":{"data":"\n\n","terminal_id":"exec-9614150a-94ad-4e61-9487-f07432792a6e"}}}}}"#,
        #"{"jsonrpc":"2.0","method":"session/update","params":{"sessionId":"01a18760-e6c1-7790-87ab-e066461b106f","update":{"sessionUpdate":"tool_call_update","toolCallId":"exec-9614150a-94ad-4e61-9487-f07432792a6e","_meta":{"terminal_output_delta":{"data":"\n\n","terminal_id":"exec-9614150a-94ad-4e61-9487-f07432792a6e"}}}}}"#,
        #"{"jsonrpc":"2.0","method":"session/update","params":{"sessionId":"01a18760-e6c1-7790-87ab-e066461b106f","update":{"sessionUpdate":"tool_call_update","toolCallId":"exec-9614150a-94ad-4e61-9487-f07432792a6e","_meta":{"terminal_output_delta":{"data":"\n\n","terminal_id":"exec-9614150a-94ad-4e61-9487-f07432792a6e"}}}}}"#,
        #"{"jsonrpc":"2.0","method":"session/update","params":{"sessionId":"01a18760-e6c1-7790-87ab-e066461b106f","update":{"sessionUpdate":"tool_call_update","toolCallId":"exec-9614150a-94ad-4e61-9487-f07432792a6e","_meta":{"terminal_output_delta":{"data":".","terminal_id":"exec-9614150a-94ad-4e61-9487-f07432792a6e"}}}}}"#,
        #"{"jsonrpc":"2.0","method":"session/update","params":{"sessionId":"01a18760-e6c1-7790-87ab-e066461b106f","update":{"sessionUpdate":"tool_call_update","toolCallId":"exec-9614150a-94ad-4e61-9487-f07432792a6e","_meta":{"terminal_output_delta":{"data":".\n----------------------------------------------------------------------\nRan 2 tests in 0.000s\n\n","terminal_id":"exec-9614150a-94ad-4e61-9487-f07432792a6e"}}}}}"#,
        #"{"jsonrpc":"2.0","method":"session/update","params":{"sessionId":"01a18760-e6c1-7790-87ab-e066461b106f","update":{"sessionUpdate":"tool_call_update","toolCallId":"exec-9614150a-94ad-4e61-9487-f07432792a6e","_meta":{"terminal_output_delta":{"data":"OK\n","terminal_id":"exec-9614150a-94ad-4e61-9487-f07432792a6e"}}}}}"#,
        #"{"jsonrpc":"2.0","method":"session/update","params":{"sessionId":"01a18760-e6c1-7790-87ab-e066461b106f","update":{"sessionUpdate":"tool_call_update","toolCallId":"exec-9614150a-94ad-4e61-9487-f07432792a6e","status":"completed","_meta":{"terminal_exit":{"exit_code":0,"signal":null,"terminal_id":"exec-9614150a-94ad-4e61-9487-f07432792a6e"}}}}}"#,
    ]

    static let callIDs = [
        "exec-c7be9e48-da6a-4a50-958c-230823fff573", "exec-1ac7f4dd-6aa4-4129-ad4b-23197401f4d7",
        "exec-647719f9-a8a4-48a7-921b-31402ec5069c", "exec-63c9b889-c57d-4daf-b0b4-9b4dce84b608",
        "exec-0d5ae936-3821-4b27-9634-2d53baf63b88", "exec-9614150a-94ad-4e61-9487-f07432792a6e",
    ]
}

/// Calls in the shape codex-acp 2.2.2's `DynamicToolReporter` gives Codex's own code mode tools
/// when Codex reports the program rather than its nested calls: an `execute` call titled `exec`
/// (or `sleep`) with the program in `rawInput.arguments` and its result as text content.
enum CodexExecWire {
    static func call(_ id: String, _ program: String) -> ToolCallState {
        var call = ToolCallState(id: id, title: "exec", kind: .execute, status: .completed)
        call.name = "exec"
        call.rawInput = .object(["arguments": .string(program)])
        return call
    }

    static func sleep(_ id: String) -> ToolCallState {
        var call = ToolCallState(id: id, title: "sleep", kind: .execute, status: .completed)
        call.name = "sleep"
        call.rawInput = .object(["arguments": .object([:])])
        call.content = [.content(.text("Wall time: 30.0032 seconds\nSleep completed."))]
        return call
    }
}
