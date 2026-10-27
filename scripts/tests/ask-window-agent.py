#!/usr/bin/env python3
"""Offline ACP fixture for the ask-window regression. All content is synthetic."""
import argparse
import json
import pathlib
import sys

parser = argparse.ArgumentParser()
parser.add_argument("--project", required=True)
parser.add_argument("--store", type=pathlib.Path, required=True)
args = parser.parse_args()
args.store.mkdir(parents=True, exist_ok=True)
pending = None


def send(**message):
    print(json.dumps(dict(jsonrpc="2.0", **message)), flush=True)


def update(text):
    send(method="session/update", params=dict(sessionId="ask-window", update=dict(
        sessionUpdate="agent_message_chunk", content=dict(type="text", text=text))))


for line in sys.stdin:
    message = json.loads(line)
    if "method" not in message:
        if message.get("id") == "ask" and pending is not None:
            response = message.get("result", {})
            (args.store / "answer.json").write_text(json.dumps(response))
            update("Answer received: " + json.dumps(response))
            send(id=pending, result=dict(stopReason="end_turn"))
            pending = None
        continue
    if "id" not in message:
        continue
    method, params, result = message["method"], message.get("params", {}), {}
    if method == "initialize":
        result = dict(protocolVersion=1, agentInfo=dict(name="ask-window", version="1"), authMethods=[],
                      agentCapabilities=dict(loadSession=True, sessionCapabilities=dict(list={}, resume={})))
    elif method == "session/list":
        result = dict(sessions=[dict(sessionId="ask-window", cwd=args.project,
                      title="Review the storage choices", updatedAt="2026-10-26T02:00:00Z")])
    elif method in ("session/new", "session/load", "session/resume"):
        marker = args.store / "fail-new"
        if method == "session/new" and marker.exists():
            marker.unlink()
            detail = "The fixture could not read this setting. Review the value and retry the task. " * 100
            send(id=message["id"], error=dict(code=-32603, message=f"{args.project}/settings.toml:1:1: {detail}"))
            continue
        if method == "session/load":
            update("Ready to review the storage choices.")
        if method == "session/new":
            result["sessionId"] = "ask-window"
    elif method == "session/prompt":
        pending = message["id"]
        prompt = " ".join(part.get("text", "") for part in params.get("prompt", []))
        detail = ("Keep the settings with the turn so another client can restore the same model, effort and "
                  "permissions. Review the migration, offline behavior, rollback and compatibility before choosing. ") * 5
        schema = dict(type="object", properties=dict(question_0=dict(
            type="string", description="Where should the task record each turn's settings?",
            oneOf=[dict(const=str(i), title=f"Storage choice {i}", description=detail) for i in range(1, 10)]),
            question_0_custom=dict(type="string", title="Other")))
        request = dict(sessionId="ask-window", mode="form", message="Review the storage choices.")
        if "approval" in prompt:
            send(id="ask", method="session/request_permission", params=dict(
                sessionId="ask-window", toolCall=dict(toolCallId="long-approval", title="Review the report",
                kind="read", content=[dict(type="content", content=dict(type="text", text=detail * 6))]),
                options=[dict(optionId="allow", name="Allow", kind="allow_once"),
                         dict(optionId="reject", name="Reject", kind="reject_once")]))
            continue
        if "confirmation" in prompt:
            request["message"] = detail * 6
            request["requestedSchema"] = dict(type="object", properties={})
        else:
            request["requestedSchema"] = schema
        send(id="ask", method="elicitation/create", params=request)
        continue
    send(id=message["id"], result=result)
