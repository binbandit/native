#!/usr/bin/env python3
"""Local quote/live-reference fixture. Records only synthetic prompts in its own --store."""
import argparse
import json
import pathlib
import sys

parser = argparse.ArgumentParser()
parser.add_argument("--store", type=pathlib.Path, required=True)
parser.add_argument("--project", required=True)
args = parser.parse_args()
args.store.mkdir(parents=True, exist_ok=True)
source = "Packages/ACP/Sources/ACP/Prompt/PromptQueue.swift"
old = "\n" * 40 + "    func save(_ id: Prompt.ID, text: String) {\n        guard let index = prompts.firstIndex(where: { $0.id == id }) else { return }\n        prompts.remove(at: index)\n        prompts.append(Prompt(id: id, text: text))\n    }\n"
new = "\n" * 40 + "    func save(_ id: Prompt.ID, text: String) {\n        guard let index = prompts.firstIndex(where: { $0.id == id }) else { return }\n        let edited = Prompt(id: id, text: text)\n        prompts.remove(at: index)\n        prompts.append(edited)\n    }\n"


def send(**message):
    print(json.dumps(dict(jsonrpc="2.0", **message)), flush=True)


def update(kind, **values):
    send(method="session/update", params=dict(sessionId="quote-fixture", update=dict(sessionUpdate=kind, **values)))


def options():
    return [dict(id="model", name="Model", category="model", type="select", currentValue="gpt-6.1-sol",
                 options=[dict(value="gpt-6.1-sol", name="6.1 Sol")])]


def transcript():
    update("user_message_chunk", content=dict(type="text", text="Keep the queued message in its place when I edit it."))
    update("agent_message_chunk", content=dict(type="text", text="The edited message is now built before removing the old one. Check the final two lines."))
    update("tool_call", toolCallId="queue-diff", title="Edit PromptQueue.swift", kind="edit", status="completed",
           content=[dict(type="diff", path=source, oldText=old, newText=new)])
    update("tool_call", toolCallId="queue-tests", title="swift test --filter PromptQueueTests", kind="execute", status="completed",
           rawInput=dict(command="swift test --filter PromptQueueTests"),
           content=[dict(type="content", content=dict(type="text", text="Test editingFirstMessage started.\nExpected the edited message at index 0.\nFound it at index 2.\nTest failed."))])


for line in sys.stdin:
    message = json.loads(line)
    if "id" not in message or "method" not in message:
        continue
    method, params, result = message["method"], message.get("params", {}), {}
    if method == "initialize":
        result = dict(protocolVersion=1, agentInfo=dict(name="quote-fixture", version="1"), authMethods=[],
                      agentCapabilities=dict(loadSession=True, sessionCapabilities=dict(list={}, resume={}, close={})))
    elif method == "session/list":
        result = dict(sessions=[dict(sessionId="quote-fixture", cwd=args.project,
                      title="Keep queued messages in place", updatedAt="2026-10-24T02:00:00Z")])
    elif method in ("session/new", "session/load", "session/resume"):
        if method == "session/load":
            transcript()
        result = dict(configOptions=options())
        if method == "session/new":
            result["sessionId"] = "quote-fixture"
    elif method == "session/set_config_option":
        result = dict(configOptions=options())
    elif method == "session/prompt":
        with (args.store / "received.jsonl").open("a") as log:
            log.write(json.dumps(params) + "\n")
        update("agent_message_chunk", content=dict(type="text", text="Received the quoted lines and the full file reference."))
        result = dict(stopReason="end_turn")
    send(id=message["id"], result=result)
