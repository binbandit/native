#!/usr/bin/env python3
"""Optional, bounded Claude Code sample against Native's synthetic MCP tools."""

import argparse
import json
import os
from pathlib import Path
import shutil
import signal
import subprocess
import tempfile
import time


def command(binary, *args):
    return subprocess.run([str(binary), *args], check=True, capture_output=True, text=True).stdout


def claude_command(cli, config, instructions, budget):
    return [
        cli, "--bare", "--print", "--model", "haiku", "--effort", "low",
        "--tools", "", "--disable-slash-commands", "--setting-sources", "",
        "--strict-mcp-config", "--mcp-config", str(config),
        "--allowedTools", "mcp__native-eval__*", "--no-session-persistence",
        "--output-format", "json", "--max-budget-usd", str(budget),
        "--append-system-prompt", instructions,
    ]


def sample(binary, cli, case, output, budget, timeout):
    # Each invocation owns its process group, so timeout cleanup cannot target another session.
    started = time.monotonic()
    trace_path = output / (case["id"] + ".trace.json")
    report = {"caseID": case["id"], "model": "haiku", "effort": "low", "status": "infrastructureError"}
    with tempfile.TemporaryDirectory(prefix="native-tool-eval-") as directory:
        config = Path(directory) / "mcp.json"
        config.write_text(json.dumps({"mcpServers": {"native-eval": {
            "command": str(binary), "args": ["serve", case["id"], str(trace_path)],
        }}}))
        instructions = command(binary, "instructions") + (
            "\nThis is a synthetic Native tool-choice exercise. Only the supplied MCP tools are available. "
            "All workers, including review-agent, are in-memory fixtures, not real agents. "
            "Do not use built-in delegation or other tools. End your turn after fulfilling the request."
        )
        process = None
        try:
            process = subprocess.Popen(
                claude_command(cli, config, instructions, budget), cwd=directory,
                stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                text=True, start_new_session=True,
            )
            stdout, _ = process.communicate(case["prompt"], timeout=timeout)
            if process.returncode != 0:
                report["reason"] = "Claude Code exited unsuccessfully; check authentication and CLI compatibility."
            else:
                response = json.loads(stdout)
                report["costUSD"] = response.get("total_cost_usd")
                report["usage"] = response.get("usage")
                report["actualModels"] = sorted(response.get("modelUsage", {}))
                if response.get("is_error") or response.get("subtype") != "success":
                    report["reason"] = "Claude Code did not complete the sample (possibly budget or turn limit)."
                elif not trace_path.exists():
                    report["reason"] = "MCP server did not produce a trace."
                else:
                    trace = json.loads(trace_path.read_text())
                    trace["finalText"] = response.get("result", "")
                    trace_path.write_text(json.dumps(trace, indent=2) + "\n")
                    grade = subprocess.run(
                        [str(binary), "grade", str(trace_path)], capture_output=True, text=True,
                    )
                    if grade.returncode in (0, 1):
                        report.update(json.loads(grade.stdout))
                        report["status"] = report.pop("outcome")
                    else:
                        report["reason"] = "Grader process failed."
        except subprocess.TimeoutExpired:
            report["reason"] = "Sample exceeded wall-clock limit."
        except (ValueError, OSError):
            report["reason"] = "Invalid CLI response or trace."
        finally:
            # Also reap the synthetic MCP server if the CLI exited without closing it.
            if process is not None:
                try:
                    os.killpg(process.pid, signal.SIGTERM)
                except ProcessLookupError:
                    pass
                try:
                    process.communicate(timeout=5)
                except subprocess.TimeoutExpired:
                    os.killpg(process.pid, signal.SIGKILL)
                    process.communicate()
    report["elapsedSeconds"] = round(time.monotonic() - started, 2)
    if report["status"] == "infrastructureError" and trace_path.exists():
        trace = json.loads(trace_path.read_text())
        trace["completion"] = "infrastructureError"
        trace_path.write_text(json.dumps(trace, indent=2) + "\n")
    (output / (case["id"] + ".report.json")).write_text(json.dumps(report, indent=2) + "\n")
    return report


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--live", action="store_true", help="Explicitly allow a paid model sample")
    parser.add_argument("--case", default="wait-for-reply")
    parser.add_argument("--all", action="store_true", help="Run all cases sequentially")
    parser.add_argument("--binary", type=Path, default=Path(__file__).resolve().parents[2] /
                        "Packages/OrchestrationEvals/.build/debug/native-tool-evals")
    parser.add_argument("--claude", default="claude", help="Configured Claude Code executable")
    parser.add_argument("--output", type=Path)
    parser.add_argument("--budget-usd", type=float, default=0.05)
    parser.add_argument("--timeout", type=int, default=120)
    args = parser.parse_args()
    binary = args.binary.resolve()
    cases = json.loads(command(binary, "list"))
    selected = cases if args.all else [case for case in cases if case["id"] == args.case]
    if not selected:
        parser.error("Unknown case; use the binary's list command.")
    if not args.live:
        print(json.dumps(selected, indent=2))
        print("Offline only. Add --live and --output to run a paid Haiku sample.")
        return 0
    if not args.output or not 0 < args.budget_usd <= 0.10 or not 1 <= args.timeout <= 300:
        parser.error("Live runs require --output, a budget in (0, 0.10] USD and timeout in [1, 300] seconds.")
    command(binary, "check-live-policy")
    cli = shutil.which(args.claude)
    if not cli:
        parser.error("Claude Code is not installed; no sample was run.")
    output = args.output.resolve()
    output.mkdir(parents=True, exist_ok=True)
    if any(output.iterdir()):
        parser.error("Use an empty output directory to preserve earlier samples.")
    reports = [sample(binary, cli, case, output, args.budget_usd, args.timeout) for case in selected]
    print(json.dumps(reports, indent=2))
    return 0 if all(report["status"] == "passed" for report in reports) else 1


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (subprocess.CalledProcessError, OSError):
        raise SystemExit("Eval command failed or live policy denied the run. No provider error output was recorded.")
