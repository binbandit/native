# A fake ACP agent with long sessions to reopen, for measuring long transcripts
# (docs/performance.md, "Long transcripts"). `session/list` reports sessions named for their turn
# count ("Long session, 500 turns"), and `session/load` replays that many turns the way a coding
# agent's history looks: prompts, reasoning, commentary, reads, searches, commands with output, edits
# with diffs, and Markdown replies with headings, lists, code blocks and tables, from this repository's
# own sources. A prompt containing "stream" gets a long reply streamed at about Codex's pace.
#
#   python3 scripts/perf/long-session-agent.py --install <plugins folder>
#       writes a plugin manifest for it; launch Native with `-pluginsDirectory <plugins folder>`.
import json, os, random, sys, threading, time

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
CORPUS = [
    "native/Models/AppModel.swift", "native/Models/SessionModel.swift", "native/Views/SessionView.swift",
    "Packages/ACP/Sources/ACP/SessionState.swift", "Packages/ACP/Sources/ACP/TranscriptTurn.swift",
    "Packages/ACP/Sources/ACP/ACPConnection.swift", "Packages/ACP/Sources/ACP/JSONRPC.swift",
    "native/Plugins/PluginRegistry.swift", "scripts/perf/measure.sh", "scripts/dev/run-isolated.sh",
]

if sys.argv[1:2] == ["--install"]:
    folder = os.path.join(sys.argv[2], "long-session")
    os.makedirs(folder, exist_ok=True)
    with open(os.path.join(folder, "plugin.json"), "w") as f:
        json.dump({"id": "long-session", "name": "Long Session",
                   "description": "A fake agent whose long sessions replay a coding agent's history.",
                   "agents": [{"id": "long-session", "name": "Long Session", "symbol": "film",
                               "command": sys.executable, "args": ["-I", os.path.abspath(__file__)]}]}, f, indent=2)
    print(folder)
    sys.exit(0)

lock = threading.Lock()

def send(obj):
    with lock:
        sys.stdout.write(json.dumps(obj) + "\n")
        sys.stdout.flush()

FILES = {}
PATHS = {}
for path in CORPUS:
    name = os.path.basename(path)
    try:
        with open(os.path.join(ROOT, path)) as f:
            FILES[name] = f.read().split("\n")
        PATHS[name] = path
    except OSError:
        pass
NAMES = sorted(FILES)

WORDS = ("the transcript keeps each row laid out once so scrolling back through a long session stays "
         "smooth while the agent reads files runs commands and edits code the lazy stack measures "
         "rows as they come into view and the cache keeps parsed markdown for replies that never "
         "change again so the main thread only lays out what is new").split()

def sentence(rng, lo=8, hi=24):
    s = " ".join(rng.choice(WORDS) for _ in range(rng.randint(lo, hi)))
    return s[0].upper() + s[1:] + "."

def paragraph(rng, lo=2, hi=5):
    text = " ".join(sentence(rng) for _ in range(rng.randint(lo, hi)))
    words = text.split(" ")
    # Inline code, bold and a link, as replies have.
    for _ in range(rng.randint(0, 3)):
        i = rng.randrange(len(words))
        words[i] = rng.choice(["`%s`" % rng.choice(["SessionModel", "LazyVStack", "items", "plan()", "body"]),
                               "**%s**" % words[i], "[%s](https://example.com/%s)" % (words[i], words[i])])
    return " ".join(words)

def snippet(rng, lo=6, hi=30):
    name = rng.choice(NAMES)
    lines = FILES[name]
    n = rng.randint(lo, hi)
    start = rng.randrange(max(1, len(lines) - n))
    return name, start, lines[start:start + n]

LANGS = {"swift": "swift", "sh": "bash", "py": "python"}

def code_block(rng):
    name, _, lines = snippet(rng, 5, 28)
    lang = LANGS.get(name.rsplit(".", 1)[-1], "")
    return "```%s\n%s\n```" % (lang, "\n".join(lines))

def table(rng):
    rows = ["| File | Change | Lines |", "| --- | --- | ---: |"]
    for _ in range(rng.randint(2, 6)):
        rows.append("| `%s` | %s | +%d −%d |" % (rng.choice(list(PATHS.values())), sentence(rng, 3, 7).rstrip("."),
                                                 rng.randint(1, 90), rng.randint(0, 40)))
    return "\n".join(rows)

def reply(rng):
    parts = []
    if rng.random() < 0.4:
        parts.append("## " + sentence(rng, 2, 5).rstrip("."))
    parts.append(paragraph(rng))
    for _ in range(rng.randint(1, 4)):
        r = rng.random()
        if r < 0.3:
            parts.append("\n".join("- " + sentence(rng, 4, 14) for _ in range(rng.randint(2, 6))))
        elif r < 0.45:
            parts.append("\n".join("%d. %s" % (i + 1, sentence(rng, 4, 14)) for i in range(rng.randint(2, 5))))
        elif r < 0.75:
            parts.append(code_block(rng))
        elif r < 0.85:
            parts.append(table(rng))
        else:
            parts.append("### " + sentence(rng, 2, 4).rstrip("."))
        parts.append(paragraph(rng, 1, 3))
    return "\n\n".join(parts)

def update(sid, u):
    send({"jsonrpc": "2.0", "method": "session/update", "params": {"sessionId": sid, "update": u}})

def message(sid, kind, text, mid):
    update(sid, {"sessionUpdate": kind, "messageId": mid, "content": {"type": "text", "text": text}})

def tool(sid, rng, tid):
    r = rng.random()
    name, start, lines = snippet(rng, 10, 60)
    path = PATHS[name]
    if r < 0.3:
        update(sid, {"sessionUpdate": "tool_call", "toolCallId": tid, "name": "exec_command", "kind": "read",
                     "title": "Read %s" % name, "status": "completed",
                     "locations": [{"path": "/tmp/long-session/" + path, "line": start + 1}],
                     "rawInput": {"command": "sed -n '%d,%dp' %s" % (start + 1, start + len(lines), path)}})
        update(sid, {"sessionUpdate": "tool_call_update", "toolCallId": tid,
                     "_meta": {"terminal_output_delta": {"data": "\n".join(lines) + "\n", "terminal_id": tid},
                               "terminal_exit": {"exit_code": 0, "signal": None, "terminal_id": tid}}})
    elif r < 0.5:
        term = rng.choice(["markdownSections", "LazyVStack", "onGeometryChange", "SessionState", "items"])
        hits = "\n".join("%s:%d:%s" % (PATHS[rng.choice(NAMES)], rng.randint(1, 400), l.strip()[:100])
                         for l in lines[:rng.randint(3, 12)])
        update(sid, {"sessionUpdate": "tool_call", "toolCallId": tid, "name": "exec_command", "kind": "search",
                     "title": "Search %s in native" % term, "status": "completed",
                     "rawInput": {"command": "rg -n %s native" % term}})
        update(sid, {"sessionUpdate": "tool_call_update", "toolCallId": tid,
                     "_meta": {"terminal_output_delta": {"data": hits + "\n", "terminal_id": tid},
                               "terminal_exit": {"exit_code": 0, "signal": None, "terminal_id": tid}}})
    elif r < 0.75:
        command = rng.choice(["swift test --package-path Packages/ACP", "git status --short", "just build",
                              "swift format lint --strict %s" % path, "xcodebuild -scheme native build | tail -20"])
        output = "\n".join(sentence(rng, 3, 12) for _ in range(rng.randint(2, 30)))
        update(sid, {"sessionUpdate": "tool_call", "toolCallId": tid, "name": "exec_command", "kind": "execute",
                     "title": command, "status": "completed",
                     "content": [{"type": "terminal", "terminalId": tid}],
                     "rawInput": {"command": command, "cwd": "/tmp/long-session"},
                     "_meta": {"terminal_info": {"cwd": "/tmp/long-session", "terminal_id": tid}}})
        failed = rng.random() < 0.1
        update(sid, {"sessionUpdate": "tool_call_update", "toolCallId": tid,
                     "status": "failed" if failed else "completed",
                     "_meta": {"terminal_output_delta": {"data": output + "\n", "terminal_id": tid},
                               "terminal_exit": {"exit_code": 1 if failed else 0, "signal": None, "terminal_id": tid}}})
    else:
        old = "\n".join(lines) + "\n"
        new_lines = list(lines)
        for _ in range(rng.randint(1, 6)):
            i = rng.randrange(len(new_lines))
            if rng.random() < 0.5:
                new_lines[i] = new_lines[i] + "  // " + sentence(rng, 3, 8)
            else:
                new_lines.insert(i, "    " + sentence(rng, 3, 10).replace(".", "()"))
        update(sid, {"sessionUpdate": "tool_call", "toolCallId": tid, "name": "apply_patch", "kind": "edit",
                     "title": "Edit %s" % path, "status": "completed",
                     "locations": [{"path": "/tmp/long-session/" + path}],
                     "content": [{"type": "diff", "path": "/tmp/long-session/" + path,
                                  "oldText": old, "newText": "\n".join(new_lines) + "\n"}]})

def replay(sid, turns):
    for t in range(turns):
        rng = random.Random(t)
        prompt = sentence(rng, 6, 30)
        if rng.random() < 0.2:
            prompt += "\n\n" + sentence(rng, 5, 20)
        message(sid, "user_message_chunk", prompt, "u%d" % t)
        if rng.random() < 0.6:
            message(sid, "agent_thought_chunk", "**%s**\n\n%s" % (sentence(rng, 2, 4).rstrip("."), paragraph(rng, 1, 3)),
                    "t%d" % t)
        n = 0
        for phase in range(rng.randint(1, 4)):
            if rng.random() < 0.6:
                message(sid, "agent_message_chunk", sentence(rng, 6, 20), "c%d-%d" % (t, phase))
            for _ in range(rng.randint(1, 6)):
                tool(sid, rng, "call-%d-%d" % (t, n))
                n += 1
        message(sid, "agent_message_chunk", reply(rng), "r%d" % t)

def sessions(cwd):
    return [{"sessionId": "long-%d" % n, "cwd": cwd, "title": "Long session, %d turns" % n,
             "updatedAt": "2026-10-19T0%d:00:00Z" % i} for i, n in enumerate([500, 100, 20])]

counter = 0
for line in sys.stdin:
    try:
        msg = json.loads(line)
    except ValueError:
        continue
    method, rid, params = msg.get("method"), msg.get("id"), msg.get("params") or {}
    if rid is None:
        continue
    if method == "initialize":
        send({"jsonrpc": "2.0", "id": rid, "result": {
            "protocolVersion": 1,
            "agentCapabilities": {"loadSession": True, "sessionCapabilities": {"list": {}}},
            "agentInfo": {"name": "replayer", "version": "0.0.1"}, "authMethods": []}})
    elif method == "session/list":
        cwd = params.get("cwd") or "/tmp/long-session"
        send({"jsonrpc": "2.0", "id": rid, "result": {"sessions": sessions(cwd)}})
    elif method == "session/load":
        sid = params.get("sessionId", "long-20")
        try:
            turns = int(sid.rsplit("-", 1)[-1])
        except ValueError:
            turns = 20
        replay(sid, turns)
        send({"jsonrpc": "2.0", "id": rid, "result": {}})
    elif method == "session/new":
        counter += 1
        send({"jsonrpc": "2.0", "id": rid, "result": {"sessionId": "new-%d-%d" % (int(time.time()), counter)}})
    elif method == "session/prompt":
        sid = params.get("sessionId")
        text = " ".join(b.get("text", "") for b in params.get("prompt", []) if isinstance(b, dict))
        def stream(rid=rid, sid=sid, text=text):
            mid = "live-%d" % time.time_ns()
            if "stream" in text:
                # About Codex's pace: 4 to 30 characters every 45 ms, a long reply with code blocks.
                rng = random.Random(7)
                body = "\n\n".join(reply(rng) for _ in range(12))
                i = 0
                while i < len(body):
                    n = rng.randint(4, 30)
                    message(sid, "agent_message_chunk", body[i:i + n], mid)
                    i += n
                    time.sleep(0.045)
            else:
                message(sid, "agent_message_chunk", "OK.", mid)
            send({"jsonrpc": "2.0", "id": rid, "result": {"stopReason": "end_turn"}})
        threading.Thread(target=stream, daemon=True).start()
    else:
        send({"jsonrpc": "2.0", "id": rid, "error": {"code": -32601, "message": "Method not found: " + str(method)}})
