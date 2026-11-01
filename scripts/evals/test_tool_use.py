import importlib.util
import json
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest.mock import patch


SPEC = importlib.util.spec_from_file_location("tool_use", Path(__file__).with_name("tool-use.py"))
RUNNER = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(RUNNER)
BINARY = Path(__file__).resolve().parents[2] / "Packages/OrchestrationEvals/.build/debug/native-tool-evals"


class ToolUseRunnerTests(unittest.TestCase):
    def test_live_command_is_cheap_and_isolated(self):
        command = RUNNER.claude_command("claude", "/tmp/config", "instructions", 0.05)
        for flag, value in [("--model", "haiku"), ("--effort", "low"), ("--tools", ""),
                            ("--setting-sources", ""), ("--max-budget-usd", "0.05")]:
            self.assertEqual(command[command.index(flag) + 1], value)
        for flag in ["--bare", "--strict-mcp-config", "--no-session-persistence", "--disable-slash-commands"]:
            self.assertIn(flag, command)

    def test_default_never_starts_claude_or_checks_live_policy(self):
        with patch("sys.argv", ["tool-use.py"]), patch.object(RUNNER, "command", return_value=json.dumps([
            {"id": "wait-for-reply", "prompt": "Wait"},
        ])) as command, patch.object(RUNNER, "sample") as sample, patch("builtins.print"):
            self.assertEqual(RUNNER.main(), 0)
            sample.assert_not_called()
            self.assertEqual(command.call_args.args[1:], ("list",))

    @unittest.skipUnless(BINARY.exists(), "Build OrchestrationEvals first")
    def test_mcp_stdio_records_real_handler_wire_and_grades(self):
        requests = [
            {"id": 1, "method": "initialize", "params": {"protocolVersion": "2025-03-26"}},
            {"method": "notifications/initialized"},
            {"id": 2, "method": "tools/list"},
            {"id": 3, "method": "tools/call", "params": {"name": "get_task", "arguments": {"task_id": "task-cache"}}},
            {"id": 4, "method": "missing-method"},
            {"id": 5, "method": "tools/call", "params": {}},
        ]
        with tempfile.TemporaryDirectory() as directory:
            trace = Path(directory) / "trace.json"
            response = subprocess.run(
                [str(BINARY), "serve", "read-referenced-task", str(trace)],
                input="\n".join(json.dumps({"jsonrpc": "2.0", **request}) for request in requests) + "\n",
                capture_output=True, text=True, check=True, timeout=20,
            )
            messages = [json.loads(line) for line in response.stdout.splitlines()]
            self.assertEqual(len(messages), 5)
            self.assertEqual(messages[0]["result"]["protocolVersion"], "2025-03-26")
            self.assertEqual(len(messages[1]["result"]["tools"]), 7)
            self.assertEqual(messages[2]["result"]["structuredContent"]["reply"], "Cache expiry skips empty entries.")
            self.assertEqual(messages[3]["error"]["code"], -32601)
            self.assertEqual(messages[4]["error"]["code"], -32602)
            data = json.loads(trace.read_text())
            self.assertEqual(data["calls"][0]["tool"], "get_task")
            data["finalText"] = "Cache expiry skips empty entries."
            trace.write_text(json.dumps(data))
            grade = json.loads(RUNNER.command(BINARY, "grade", str(trace)))
            self.assertEqual(grade["outcome"], "passed")

    def test_timeout_and_failed_cli_are_infrastructure_errors(self):
        with tempfile.TemporaryDirectory() as directory, patch.object(RUNNER, "command", return_value="instructions"), \
                patch.object(RUNNER.subprocess, "Popen") as popen, patch.object(RUNNER.os, "killpg") as kill:
            process = popen.return_value
            process.pid = 123
            process.communicate.side_effect = [subprocess.TimeoutExpired("claude", 1), ("", "")]
            report = RUNNER.sample(BINARY, "claude", {"id": "test", "prompt": "Wait"}, Path(directory), 0.05, 1)
            self.assertEqual(report["status"], "infrastructureError")
            kill.assert_called_once()
            process.communicate.side_effect = None
            process.communicate.return_value = ("", "private error output")
            process.returncode = 1
            report = RUNNER.sample(BINARY, "claude", {"id": "test", "prompt": "Wait"}, Path(directory), 0.05, 1)
            self.assertEqual(report["status"], "infrastructureError")
            self.assertNotIn("private error output", json.dumps(report))

    def test_policy_denial_prevents_cli_launch(self):
        with patch("sys.argv", ["tool-use.py", "--live", "--output", "/tmp/not-created"]), \
                patch.object(RUNNER, "command", side_effect=[json.dumps([
                    {"id": "wait-for-reply", "prompt": "Wait"},
                ]), subprocess.CalledProcessError(1, "check-live-policy")]), \
                patch.object(RUNNER, "sample") as sample:
            with self.assertRaises(subprocess.CalledProcessError):
                RUNNER.main()
            sample.assert_not_called()

    @unittest.skipUnless(BINARY.exists(), "Build OrchestrationEvals first")
    def test_sample_report_with_local_cli_fixture(self):
        with tempfile.TemporaryDirectory() as directory:
            cli = Path(directory) / "fixture-cli"
            cli.write_text('''#!/usr/bin/env python3
import json, subprocess, sys
from pathlib import Path
config = json.loads(Path(sys.argv[sys.argv.index("--mcp-config") + 1]).read_text())
server = config["mcpServers"]["native-eval"]
request = {"jsonrpc": "2.0", "id": 1, "method": "tools/call",
           "params": {"name": "get_task", "arguments": {"task_id": "task-cache"}}}
response = subprocess.run([server["command"], *server["args"]],
                          input=json.dumps(request) + "\\n", text=True, capture_output=True, check=True)
reply = json.loads(response.stdout)["result"]["structuredContent"]["reply"]
print(json.dumps({"subtype": "success", "is_error": False, "result": reply,
                  "total_cost_usd": 0, "usage": {"input_tokens": 1}, "modelUsage": {"fixture-haiku": {}}}))
''')
            cli.chmod(0o700)
            report = RUNNER.sample(BINARY, str(cli), {"id": "read-referenced-task", "prompt": "Read"},
                                   Path(directory), 0.05, 20)
            self.assertEqual(report["status"], "passed")
            self.assertEqual(report["costUSD"], 0)
            self.assertEqual(report["actualModels"], ["fixture-haiku"])
            self.assertEqual(report["usage"], {"input_tokens": 1})


if __name__ == "__main__":
    unittest.main()
