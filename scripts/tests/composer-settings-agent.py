#!/usr/bin/env python3
"""Local ACP fixture for the Fine print popover. No commands, network or credentials.

Install as an isolated instance's plugin with command /usr/bin/python3 and args
[this file, --store, <own temporary folder>, --project, <fixture repository>].
Send 'many models', 'no settings', 'restore settings' or 'fail next setting' to
exercise those states. received.jsonl records only this fixture's config picks.
"""

import argparse
import json
import pathlib
import sys


def option(identifier, name, category, current, choices):
    return dict(id=identifier, name=name, category=category, type="select",
                currentValue=current, options=[dict(value=v, name=n) for v, n in choices])


parser = argparse.ArgumentParser()
parser.add_argument("--store", type=pathlib.Path, required=True)
parser.add_argument("--project", required=True)
args = parser.parse_args()
args.store.mkdir(parents=True, exist_ok=True)
state_file = args.store / "settings.json"
state = json.loads(state_file.read_text()) if state_file.exists() else {}
fail_next = False
many = False
empty = False


def options():
    if empty:
        return []
    models = [("gpt-6.1-sol", "6.1 Sol"), ("gpt-6.1-terra", "6.1 Terra"), ("gpt-6.1-luna", "6.1 Luna")]
    if many:
        models += [(f"gateway-{i}", f"Gateway model {i}") for i in range(1, 35)]
    return [
        option("model", "Model", "model", state.get("model", "gpt-6.1-sol"), models),
        option("effort", "Effort", "thought_level", state.get("effort", "low"),
               [(x, x.title()) for x in ["minimal", "low", "medium", "high"]]),
        option("mode", "Permissions", "mode", state.get("mode", "workspace-write"),
               [("read-only", "Read only"), ("workspace-write", "Workspace write"),
                ("agent-full-access", "Full access")]),
        option("web_search", "Web search", "web_search", state.get("web_search", "on"),
               [("on", "On"), ("off", "Off")]),
        option("agent", "Agent", "other", state.get("agent", "default"),
               [("default", "Default"), ("reviewer", "Reviewer")]),
    ]


def send(message):
    print(json.dumps(dict(jsonrpc="2.0", **message)), flush=True)


def update(kind, **values):
    send(dict(method="session/update", params=dict(sessionId="composer-fixture",
              update=dict(sessionUpdate=kind, **values))))


for line in sys.stdin:
    message = json.loads(line)
    if "id" not in message or "method" not in message:
        continue
    identifier = message["id"]
    method = message["method"]
    params = message.get("params", {})
    result = {}
    if method == "initialize":
        result = dict(protocolVersion=1, agentInfo=dict(name="composer-fixture", version="1"),
                      authMethods=[], agentCapabilities=dict(loadSession=True,
                      sessionCapabilities=dict(list={}, resume={}, close={})))
    elif method == "session/list":
        result = dict(sessions=[dict(sessionId="composer-fixture", cwd=args.project,
                      title="Keep queued messages in place", updatedAt="2026-10-24T02:00:00Z")])
    elif method in ("session/new", "session/load", "session/resume"):
        if method == "session/load":
            update("user_message_chunk", content=dict(type="text", text="Keep the queued message in its place when I edit it."))
            update("agent_message_chunk", content=dict(type="text", text="The queue now preserves its order. The updated tests cover editing, moving and sending a queued message."))
        result = dict(configOptions=options())
        if method == "session/new":
            result["sessionId"] = "composer-fixture"
    elif method == "session/set_config_option":
        with (args.store / "received.jsonl").open("a") as log:
            log.write(json.dumps(params) + "\n")
        if fail_next:
            fail_next = False
            send(dict(id=identifier, error=dict(code=-32603, message="Fixture rejected this setting. Try again.")))
            continue
        state[params["configId"]] = params["value"]
        state_file.write_text(json.dumps(state))
        update("config_option_update", configOptions=options())
        result = dict(configOptions=options())
    elif method == "session/prompt":
        text = " ".join(part.get("text", "") for part in params.get("prompt", []))
        if text == "fail next setting":
            fail_next = True
        elif text == "many models":
            many = True
        elif text == "no settings":
            empty = True
        elif text == "restore settings":
            empty = many = False
        update("config_option_update", configOptions=options())
        update("agent_message_chunk", content=dict(type="text", text="Ready. Your message is kept with this task."))
        result = dict(stopReason="end_turn")
    send(dict(id=identifier, result=result))
