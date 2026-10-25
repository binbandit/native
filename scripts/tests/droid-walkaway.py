#!/usr/bin/env python3
"""The droid side of the walk-away test (docs/droid-walkaway.md).

Runs on the droid, against one job-owned development host and nothing else:

  fixture   make the fixture repository the walk-away task works in
  host      start, stop, restart or show the job's development host (a launchd job for this login only)
  setup     put that host's task worktrees in the job folder and list the fixture as one of its projects
  pair      print a single-use pairing link for that host
  gateway   stand-in for a lost network: turn that host's listener for paired devices off and on
  observe   record the host's side: the paired Mac's connection, the task, notifications, fixture marks
  operator  turn the main Mac's sleep record and clock samples into the operator file (no machine access)
  verify    check a timeline against the operator file and print the evidence record
  clock     print this machine's clock, for measuring skew from the Mac

It never sleeps or wakes a machine, never connects to another machine, never reads credentials, and
refuses any app, launchd label or host folder that isn't a development build's own.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import plistlib
import re
import socket
import subprocess
import sys
import time
from pathlib import Path

PROTOCOL_VERSION = 2
CLIENT = {"name": "droid-walkaway", "version": "1", "build": "1"}
CHANNEL = re.compile(r"^[0-9a-f]{10}$")


class Refused(Exception):
    """A target this helper must never act on."""


# MARK: - The job's development host


class DevHost:
    """A development build's host, checked from the build's own launchd plist."""

    def __init__(self, app: Path, label: str, channel: str, program: Path, plist: dict):
        self.app = app
        self.label = label
        self.channel = channel
        self.program = program
        self.plist = plist

    @property
    def directory(self) -> Path:
        return Path.home() / "Library/Application Support/Native/Channels" / self.channel

    @property
    def socket_path(self) -> Path:
        return self.directory / "host.sock"

    @property
    def link_socket_path(self) -> Path:
        return self.directory / "Link/link.sock"

    @property
    def domain_label(self) -> str:
        return f"gui/{os.getuid()}/{self.label}"

    @property
    def environment(self) -> dict:
        return {"NATIVE_HOST_CHANNEL": self.channel, "NATIVE_HOST_DEVELOPMENT": "1"}

    def identity(self) -> dict:
        return {"label": self.label, "channel": self.channel, "bundle": bundle_id(self.app)}


def bundle_id(app: Path) -> str:
    try:
        with open(app / "Contents/Info.plist", "rb") as file:
            return str(plistlib.load(file).get("CFBundleIdentifier", ""))
    except OSError:
        return ""


def dev_host(app: Path, name: str) -> DevHost:
    """The host of `app`, only when `app` is `name`'s development build. Raises `Refused` for
    the installed Native, a Release or Nightly build, or any label without a development channel."""
    app = app.expanduser().resolve()
    installed = (Path("/Applications/Native.app"), Path.home() / "Applications/Native.app")
    if any(app == path.resolve() for path in installed):
        raise Refused(f"{app} is an installed Native; only a development build's host may be used")
    identifier = bundle_id(app)
    if not identifier.endswith(f".dev.{name}"):
        raise Refused(f"{app} is not {name}'s development build (bundle id {identifier or 'unreadable'})")
    try:
        with open(app / "Contents/Library/LaunchAgents/NativeHost.plist", "rb") as file:
            plist = plistlib.load(file)
    except OSError as error:
        raise Refused(f"{app} has no host plist: {error}") from error
    label = str(plist.get("Label", ""))
    environment = plist.get("EnvironmentVariables") or {}
    channel = str(environment.get("NATIVE_HOST_CHANNEL", ""))
    if not CHANNEL.match(channel) or environment.get("NATIVE_HOST_DEVELOPMENT") != "1":
        raise Refused(f"{app}'s host isn't on a development channel (channel {channel or 'none'})")
    if label != f"{identifier}.host.{channel}" or ".dev." not in label:
        raise Refused(f"{label or 'no label'} isn't a development host label")
    program = app / str(plist.get("BundleProgram", ""))
    return DevHost(app, label, channel, program, plist)


def job_root(path: str) -> Path:
    """The job's own folder: absolute, inside the home folder and never the home folder itself or
    anything Native owns."""
    root = Path(path).expanduser().resolve()
    home = Path.home().resolve()
    if root == home or home not in root.parents:
        raise Refused(f"{root} must be a folder of its own inside {home}")
    for owned in ("Applications", "Library", ".native"):
        if root == home / owned or (home / owned) in root.parents:
            raise Refused(f"{root} is inside ~/{owned}, which belongs to installed apps")
    return root


# MARK: - JSON-RPC over the host's Unix sockets


class Peer:
    """One newline-delimited JSON-RPC 2.0 connection, as the host and its gateway speak it."""

    def __init__(self, path: Path, timeout: float = 10):
        self.socket = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        self.socket.settimeout(timeout)
        self.socket.connect(str(path))
        self.buffer = b""
        self.next_id = 0

    def call(self, method: str, params: dict | None = None):
        self.next_id += 1
        request = {"jsonrpc": "2.0", "id": self.next_id, "method": method, "params": params or {}}
        self.socket.sendall(json.dumps(request).encode() + b"\n")
        while True:
            message = self._read()
            if message.get("id") != self.next_id or "method" in message:
                continue
            if "error" in message:
                raise RuntimeError(f"{method}: {message['error'].get('message', message['error'])}")
            return message.get("result")

    def _read(self) -> dict:
        while b"\n" not in self.buffer:
            chunk = self.socket.recv(65536)
            if not chunk:
                raise ConnectionError("the host closed the connection")
            self.buffer += chunk
        line, self.buffer = self.buffer.split(b"\n", 1)
        return json.loads(line) if line.strip() else {}

    def close(self):
        self.socket.close()


def host_peer(host: DevHost, timeout: float = 10) -> tuple[Peer, dict]:
    peer = Peer(host.socket_path, timeout)
    info = peer.call("initialize", {"protocolVersion": PROTOCOL_VERSION, "clientInfo": CLIENT})
    return peer, info


# MARK: - Commands: fixture, host, setup, pair

FIXTURE_ORIGIN = "https://walkaway.invalid/native-tests/walkaway-fixture.git"

FIXTURE_RUNNER = '''#!/usr/bin/env python3
"""The walk-away fixture: a bounded task with marks the droid's observer records.

  ./walkaway next    one step; run it again each time it says so, until it prints WALKAWAY-DONE
  ./walkaway probe   one mark and an answer at once (approval and queue cases)
"""
import hashlib, json, os, subprocess, sys, time

CONFIG = __CONFIG__
HERE = os.path.dirname(os.path.abspath(__file__))
STATE = os.path.join(HERE, ".walkaway", "state.json")
RUN = hashlib.sha256(HERE.encode()).hexdigest()[:8]


def mark(event, **fields):
    os.makedirs(os.path.dirname(CONFIG["marks"]), exist_ok=True)
    with open(CONFIG["marks"], "a") as file:
        file.write(json.dumps(dict(t=time.time(), run=RUN, event=event, **fields)) + "\\n")


def load():
    try:
        with open(STATE) as file:
            return json.load(file)
    except (OSError, ValueError):
        return {"step": 0, "startedAt": None}


def save(state):
    os.makedirs(os.path.dirname(STATE), exist_ok=True)
    with open(STATE, "w") as file:
        json.dump(state, file)


def finish(state):
    total = CONFIG["before"] + CONFIG["after"]
    with open(os.path.join(HERE, "walkaway-result.txt"), "w") as file:
        file.write("steps=%d\\nresult=pass\\n" % total)
    test = subprocess.run([sys.executable, "-m", "unittest", "-q", "test_walkaway"], cwd=HERE,
                          capture_output=True, text=True)
    result = "pass" if test.returncode == 0 else "fail"
    state["done"] = result
    save(state)
    mark("done", step=total, of=total, result=result)
    print("WALKAWAY-DONE result=%s steps=%d" % (result, total))


def next_step():
    state = load()
    total = CONFIG["before"] + CONFIG["after"]
    if state.get("done"):
        print("WALKAWAY-DONE result=%s steps=%d" % (state["done"], total))
        return
    if state["startedAt"] is None:
        state["startedAt"] = time.time()
        save(state)
        mark("start", of=total)
    step = state["step"] + 1
    if step > CONFIG["before"] and CONFIG["hold"] and not os.path.exists(CONFIG["gate"]):
        if time.time() - state["startedAt"] > CONFIG["holdMax"]:
            state["done"] = "gate-timeout"
            save(state)
            mark("done", step=state["step"], of=total, result="gate-timeout")
            print("WALKAWAY-DONE result=gate-timeout steps=%d" % state["step"])
            return
        mark("hold", step=state["step"], of=total)
        deadline = time.time() + CONFIG["holdPoll"]
        while time.time() < deadline and not os.path.exists(CONFIG["gate"]):
            time.sleep(2)
        print("Still waiting for the Mac to go away. Run ./walkaway next again.")
        return
    time.sleep(CONFIG["stepSeconds"])
    state["step"] = step
    save(state)
    mark("step", step=step, of=total)
    if step >= total:
        finish(state)
    else:
        print("Step %d of %d done. Run ./walkaway next again." % (step, total))


if __name__ == "__main__":
    command = sys.argv[1] if len(sys.argv) > 1 else ""
    if command == "next":
        next_step()
    elif command == "probe":
        mark("probe")
        print("WALKAWAY-PROBE ok")
    else:
        sys.exit("usage: ./walkaway next | probe")
'''

FIXTURE_TEST = '''import os
import unittest


class WalkawayResult(unittest.TestCase):
    def test_every_step_ran(self):
        with open(os.path.join(os.path.dirname(os.path.abspath(__file__)), "walkaway-result.txt")) as file:
            fields = dict(line.split("=", 1) for line in file.read().split())
        self.assertEqual(fields["result"], "pass")
        self.assertGreater(int(fields["steps"]), 0)
'''

FIXTURE_README = """# walkaway-fixture

A bounded task for Native's walk-away test (docs/droid-walkaway.md in Native's repository). The task
runs `./walkaway next` until it prints WALKAWAY-DONE; each step leaves a mark the droid's observer
records, and the last one writes walkaway-result.txt and runs its test.

Its origin is a reserved name that never resolves: nothing here is ever fetched or pushed.
"""


def fixture(args) -> int:
    root = job_root(args.root)
    folder = root / "fixture"
    if (folder / ".git").exists() and not args.force:
        print(f"fixture already at {folder} (--force rewrites it)")
        return 0
    folder.mkdir(parents=True, exist_ok=True)
    config = {
        "marks": str(root / "evidence/marks.ndjson"),
        "gate": str(root / "evidence/gate-open"),
        "before": args.before,
        "after": args.after,
        "stepSeconds": args.step_seconds,
        "hold": not args.no_hold,
        "holdPoll": args.hold_poll,
        "holdMax": args.hold_max,
    }
    runner = folder / "walkaway"
    runner.write_text(FIXTURE_RUNNER.replace("__CONFIG__", repr(config)))
    runner.chmod(0o755)
    (folder / "test_walkaway.py").write_text(FIXTURE_TEST)
    (folder / "README.md").write_text(FIXTURE_README)
    (folder / ".gitignore").write_text(".walkaway/\n__pycache__/\n.claude/settings.local.json\n")
    git = ["git", "-C", str(folder), "-c", "user.name=Walkaway", "-c", "user.email=walkaway@example.invalid"]
    if not (folder / ".git").exists():
        subprocess.run(git + ["init", "-q", "-b", "main"], check=True)
        subprocess.run(git + ["remote", "add", "origin", FIXTURE_ORIGIN], check=True)
    subprocess.run(git + ["add", "-A"], check=True)
    subprocess.run(git + ["commit", "-q", "--allow-empty", "-m", "Walk-away fixture"], check=True)
    # Nothing is ever pushed from it, even by accident.
    subprocess.run(git + ["remote", "set-url", "--push", "origin", "no-push"], check=True)
    print(f"fixture at {folder}: {args.before} steps, then {'the gate, then ' if config['hold'] else ''}"
          f"{args.after} more, {args.step_seconds} s each")
    return 0


def launchctl(*arguments: str) -> subprocess.CompletedProcess:
    return subprocess.run(["/bin/launchctl", *arguments], capture_output=True, text=True)


def host_command(args) -> int:
    host = dev_host(Path(args.app), args.name)
    if args.action == "start":
        # As the app starts a development host (LaunchdSessionJob): its own plist, the helper by path.
        plist = dict(host.plist)
        plist.pop("BundleProgram", None)
        plist.pop("AssociatedBundleIdentifiers", None)
        plist["Program"] = str(host.program)
        host.directory.mkdir(parents=True, exist_ok=True, mode=0o700)
        path = host.directory / "launchd.plist"
        with open(path, "wb") as file:
            plistlib.dump(plist, file)
        launchctl("enable", host.domain_label)
        launchctl("bootstrap", f"gui/{os.getuid()}", str(path))
        kick = launchctl("kickstart", host.domain_label)
        if kick.returncode != 0:
            print(f"launchctl kickstart failed: {kick.stderr.strip()}", file=sys.stderr)
            return 1
    elif args.action == "restart":
        kick = launchctl("kickstart", "-k", host.domain_label)
        if kick.returncode != 0:
            print(f"launchctl kickstart -k failed: {kick.stderr.strip()}", file=sys.stderr)
            return 1
    elif args.action == "stop":
        launchctl("bootout", host.domain_label)
    listed = launchctl("print", host.domain_label)
    pid = re.search(r"^\s*pid = (\d+)", listed.stdout, re.MULTILINE)
    print(f"label {host.label}\nchannel {host.channel}\nfolder {host.directory}")
    print(f"pid {pid.group(1) if pid else 'none'}")
    return 0


def setup(args) -> int:
    host = dev_host(Path(args.app), args.name)
    root = job_root(args.root)
    worktrees = root / "worktrees"
    worktrees.mkdir(parents=True, exist_ok=True)
    peer, _ = host_peer(host)
    try:
        listed = peer.call("_native/projects/list")
        if listed.get("worktreesFolder") != str(worktrees):
            # Only the host's own machine says where worktrees go, through a catalog sync; doing it
            # before pairing keeps the catalog the paired Mac syncs next.
            if peer.call("_native/agents/list"):
                raise Refused("the host already has agents; run setup before pairing")
            peer.call("_native/agents/sync", {"agents": [], "refreshEnvironment": False,
                                              "worktreesFolder": str(worktrees)})
        listed = peer.call("_native/projects/add", {"path": str(root / "fixture"), "create": False})
    finally:
        peer.close()
    print(f"worktrees {listed.get('worktreesFolder')}")
    for project in listed.get("projects", []):
        print(f"project {project.get('path')}")
    return 0


def gateway(args) -> int:
    """Turns the job's host's listener for paired devices off and on: the stand-in for the Mac's
    network going away while the app keeps running. Pairings stay; the host's tasks keep working."""
    host = dev_host(Path(args.app), args.name)
    peer = Peer(host.link_socket_path)
    try:
        status = peer.call("link/enabled", {"isEnabled": args.state == "on"})
    finally:
        peer.close()
    listener = status.get("listener") or {}
    print(f"enabled {status.get('isEnabled')}, listener {listener.get('state')} on port {listener.get('port')}")
    return 0


def pair(args) -> int:
    host = dev_host(Path(args.app), args.name)
    environment = dict(os.environ, **host.environment)
    command = [str(host.program), "pair", "--run-commands", "--install-updates"] + (["--json"] if args.json else [])
    return subprocess.run(command, env=environment).returncode


# MARK: - Observing


def short(identifier) -> str | None:
    """A stable, short stand-in for an id, so records can be compared without carrying it whole."""
    return hashlib.sha256(str(identifier).encode()).hexdigest()[:8] if identifier else None


def title_source(summary: dict) -> str:
    titles = summary.get("titles") or {}
    for source in ("user", "generated", "fallback"):
        if titles.get(source):
            return source
    return "agent" if summary.get("title") else "none"


def session_record(summary: dict) -> dict:
    return {
        "session": short(summary.get("id")),
        "agent": summary.get("agentID"),
        "phase": summary.get("phase"),
        "needsApproval": bool(summary.get("needsApproval")),
        "queued": len(summary.get("queue") or []),
        "stopReason": summary.get("lastStopReason"),
        "title": title_source(summary),
    }


def gate_should_open(samples: list, now: float, after: float) -> bool:
    """Whether the paired Mac has gone away: seen connected since the gate was armed, then seen
    with no device connected for at least `after` seconds. `samples` is (time, connected) pairs."""
    seen_connected = False
    away_since = None
    for at, connected in samples:
        if connected:
            seen_connected, away_since = True, None
        elif seen_connected and away_since is None:
            away_since = at
    return away_since is not None and now - away_since >= after


class Observer:
    def __init__(self, host: DevHost, root: Path, args):
        self.host = host
        self.root = root
        self.args = args
        self.timeline = root / "evidence/timeline.ndjson"
        self.marks = root / "evidence/marks.ndjson"
        self.gate = root / "evidence/gate-open"
        self.timeline.parent.mkdir(parents=True, exist_ok=True)
        self.marks_offset = self.marks.stat().st_size if self.marks.exists() else 0
        self.last: dict = {}
        self.activity_after = None
        self.connection_samples: list = []
        self.last_beat = 0.0

    def write(self, record: dict):
        record = dict(t=round(time.time(), 3), **record)
        with open(self.timeline, "a") as file:
            file.write(json.dumps(record, sort_keys=True) + "\n")

    def changed(self, key: str, value) -> bool:
        if self.last.get(key) == value:
            return False
        self.last[key] = value
        return True

    def run(self) -> int:
        if self.args.arm:
            self.gate.unlink(missing_ok=True)
        info = self.identify()
        self.write({"type": "observer", "event": "start", "host": info, "gate": self.args.arm,
                    "gateAfter": self.args.gate_after, "every": self.args.every})
        deadline = time.time() + self.args.duration
        while time.time() < deadline:
            try:
                self.observe_link()
                self.observe_host()
            except (OSError, ConnectionError, RuntimeError, ValueError) as error:
                if self.changed("problem", type(error).__name__):
                    self.write({"type": "problem", "what": type(error).__name__})
            self.copy_marks()
            if time.time() - self.last_beat >= 60:
                self.last_beat = time.time()
                self.write({"type": "beat"})
            time.sleep(self.args.every)
        self.write({"type": "observer", "event": "stop"})
        return 0

    def identify(self) -> dict:
        identity = self.host.identity()
        # The doctor runs the login shell and each tool, which takes a while on a busy droid.
        peer, info = host_peer(self.host, timeout=120)
        try:
            status = peer.call("_native/host/status")
            doctor = peer.call("_native/host/doctor")
        finally:
            peer.close()
        hello = info.get("hostInfo") or {}
        identity.update({
            "hostID": short(info.get("hostID")),
            "channelReported": info.get("channel"),
            "version": hello.get("version"),
            "build": hello.get("build"),
            "startedAt": (info.get("startedAt") or 0) / 1000,
            "system": status.get("system"),
            "keepAwake": ((status.get("keepAwake") or {}).get("policy") or {}).get("mode"),
            "tools": {check.get("id"): check.get("status") for check in doctor.get("checks", [])},
        })
        return identity

    def observe_link(self):
        peer = Peer(self.host.link_socket_path)
        try:
            status = peer.call("link/status")
        finally:
            peer.close()
        active = [entry for entry in status.get("devices", []) if not (entry.get("device") or {}).get("revokedAt")]
        connected = sum(1 for entry in active if entry.get("isConnected"))
        now = time.time()
        self.connection_samples.append((now, connected > 0))
        if self.changed("link", (len(active), connected, status.get("isEnabled"))):
            self.write({"type": "link", "paired": len(active), "connected": connected,
                        "enabled": status.get("isEnabled")})
        if self.args.arm and not self.gate.exists() and gate_should_open(
                self.connection_samples, now, self.args.gate_after):
            self.gate.write_text(f"{now}\n")
            self.write({"type": "gate", "event": "open"})

    def observe_host(self):
        peer, info = host_peer(self.host)
        try:
            if self.changed("epoch", info.get("epoch")):
                self.write({"type": "host", "epoch": short(info.get("epoch")), "pid": info.get("processID")})
            for summary in peer.call("session/list") or []:
                record = session_record(summary)
                if self.changed(f"session:{record['session']}", record):
                    self.write(dict(type="session", **record))
            entries = peer.call("_native/activity/list", {"after": self.activity_after, "limit": 200}) or []
            if isinstance(entries, dict):
                entries = entries.get("entries", [])
            for entry in entries:
                self.activity_after = max(self.activity_after or 0, entry.get("id", 0))
                self.write({"type": "activity", "id": entry.get("id"), "at": (entry.get("at") or 0) / 1000,
                            "kind": entry.get("kind"), "session": short(entry.get("sessionID"))})
            notifications = peer.call("_native/notifications/list", {"limit": 200}) or {}
            for item in notifications.get("notifications", []):
                record = {"id": item.get("id"), "at": (item.get("at") or 0) / 1000, "kind": item.get("kind"),
                          "state": item.get("state"), "session": short(item.get("sessionID")),
                          "clearedAt": (item.get("clearedAt") or 0) / 1000 or None}
                if self.changed(f"notification:{record['id']}", record):
                    self.write(dict(type="notification", **record))
        finally:
            peer.close()

    def copy_marks(self):
        if not self.marks.exists():
            return
        with open(self.marks) as file:
            file.seek(self.marks_offset)
            lines = file.readlines()
            self.marks_offset = file.tell()
        for line in lines:
            try:
                mark = json.loads(line)
            except ValueError:
                continue
            self.write({"type": "mark", "at": mark.get("t"), "run": mark.get("run"), "event": mark.get("event"),
                        "step": mark.get("step"), "of": mark.get("of"), "result": mark.get("result")})


def observe(args) -> int:
    host = dev_host(Path(args.app), args.name)
    return Observer(host, job_root(args.root), args).run()


# MARK: - The operator's record and the verdict


def clock_offset(samples: list) -> tuple[float, float]:
    """The droid's clock minus the Mac's, from (mac before, droid, mac after) samples: the sample
    with the shortest round trip, give or take half of it."""
    if not samples:
        raise ValueError("no clock samples")
    before, remote, after = min(samples, key=lambda sample: sample[2] - sample[0])
    if after < before:
        raise ValueError("a clock sample ends before it starts")
    return remote - (before + after) / 2, (after - before) / 2


def sleep_window(beats: list, interval: float) -> tuple[float, float]:
    """The Mac's sleep from its heartbeat file: the longest gap, bounded inward by one interval on
    each side, so the window is never wider than the sleep was."""
    beats = sorted(beats)
    if len(beats) < 2:
        raise ValueError("the heartbeat needs beats on both sides of the sleep")
    start, end = max(zip(beats, beats[1:]), key=lambda pair: pair[1] - pair[0])
    if end - start < 4 * interval:
        raise ValueError(f"no gap longer than {4 * interval:.0f} s in the heartbeat: the Mac never slept")
    return start + interval, end - interval


def operator(args) -> int:
    samples = [tuple(float(part) for part in sample.split(",")) for sample in args.clock]
    offset, uncertainty = clock_offset(samples)
    record = {"version": 1, "instance": args.instance, "build": args.build, "sources": []}
    if args.heartbeat:
        beats = [float(line) for line in Path(args.heartbeat).read_text().split()]
        slept, woke = sleep_window(beats, args.interval)
        record.update(sleptAt=slept, wokeAt=woke)
        record["sources"].append("heartbeat")
    if args.kern_sleep is not None and args.kern_wake is not None:
        # The kernel keeps only the last sleep and wake. They replace the heartbeat's estimate only
        # when both fall in its gap: a maintenance wake in between makes them another sleep's.
        if "sleptAt" not in record:
            record.update(sleptAt=args.kern_sleep, wokeAt=args.kern_wake)
            record["sources"].append("kern.sleeptime/kern.waketime")
        elif all(record["sleptAt"] - args.interval <= at <= record["wokeAt"] + args.interval
                 for at in (args.kern_sleep, args.kern_wake)):
            record.update(sleptAt=args.kern_sleep, wokeAt=args.kern_wake)
            record["sources"].append("kern.sleeptime/kern.waketime")
        else:
            record["notes"] = ["the kernel's last sleep isn't the heartbeat's gap; left out"]
    if args.stand_in:
        if "sleptAt" in record or args.away_from is None or args.away_until is None:
            raise ValueError("a stand-in gives --away-from and --away-until, and no sleep record")
        record.update(sleptAt=args.away_from, wokeAt=args.away_until)
        record["sources"].append(f"stand-in: {args.stand_in}")
    if "sleptAt" not in record:
        raise ValueError("give the heartbeat file or the kernel's sleep and wake times")
    record["clock"] = {"offset": offset, "uncertainty": uncertainty, "samples": len(samples)}
    text = json.dumps(record, indent=2, sort_keys=True)
    if args.output:
        Path(args.output).write_text(text + "\n")
    print(text)
    return 0


REAL_SLEEP = ("heartbeat", "kern.sleeptime/kern.waketime")


def load_timeline(path: Path) -> list:
    records = []
    for line in path.read_text().splitlines():
        if line.strip():
            records.append(json.loads(line))
    return records


def assess(timeline: list, record: dict | None, run: str | None = None) -> list:
    """Each acceptance assertion as (name, passed, detail). Times are the droid's clock."""
    results = []

    def check(name: str, passed: bool, detail: str):
        results.append((name, bool(passed), detail))

    starts = [entry for entry in timeline if entry.get("type") == "observer" and entry.get("event") == "start"]
    host = (starts[-1] if starts else {}).get("host") or {}
    label, channel = host.get("label") or "", host.get("channel") or ""
    check("development host", ".dev." in label and CHANNEL.match(channel) and host.get("channelReported") == channel,
          f"label {label or 'none'}, channel {channel or 'none'}")
    if record is None:
        check("operator record", False, "missing: the Mac's sleep and wake were not recorded")
        return results
    slept, woke = record.get("sleptAt"), record.get("wokeAt")
    clock = record.get("clock") or {}
    if slept is None or woke is None or woke <= slept or "offset" not in clock:
        check("operator record", False, "needs sleptAt before wokeAt and a measured clock offset")
        return results
    sources = record.get("sources", [])
    check("operator record", True, f"{woke - slept:.0f} s away, from {', '.join(sources)}")
    # A quit, a lock or a dropped connection rehearses the run; only the Mac's own sleep record counts.
    check("real sleep", any(source in REAL_SLEEP for source in sources),
          "the Mac's heartbeat or kernel sleep record" if any(source in REAL_SLEEP for source in sources)
          else "a stand-in, never the acceptance run")
    margin = clock.get("uncertainty", 0) + 1
    sleep_start, sleep_end = slept + clock["offset"] + margin, woke + clock["offset"] - margin

    marks = [entry for entry in timeline if entry.get("type") == "mark" and (run is None or entry.get("run") == run)]
    done = [mark for mark in marks if mark.get("event") == "done"]
    if run is None and done:
        run = done[-1].get("run")
        marks = [mark for mark in marks if mark.get("run") == run]
        done = [mark for mark in marks if mark.get("event") == "done"]
    working = [mark for mark in marks if mark.get("event") in ("start", "step", "hold")]
    check("working before sleep", any(mark["at"] < sleep_start for mark in working),
          f"{sum(1 for mark in working if mark['at'] < sleep_start)} marks before the sleep")
    check("working during sleep", any(sleep_start < mark["at"] < sleep_end for mark in working),
          f"{sum(1 for mark in working if sleep_start < mark['at'] < sleep_end)} marks while asleep")
    finished = done[-1] if done else None
    if finished is None:
        check("finished while asleep", False, "the fixture never finished")
        return results
    at = finished["at"]
    check("finished while asleep", sleep_start < at < sleep_end,
          f"{at - (slept + clock['offset']):.0f} s after the sleep and {woke + clock['offset'] - at:.0f} s before "
          f"the wake, margin {margin:.1f} s")
    check("fixture result", finished.get("result") == "pass", f"result {finished.get('result')}")

    turns = [entry for entry in timeline if entry.get("type") == "activity" and entry.get("kind") == "turnFinished"
             and entry.get("at", 0) >= at - 1]
    turn_at = turns[0]["at"] if turns else None
    check("turn ended while asleep", turn_at is not None and sleep_start < turn_at < sleep_end,
          f"turnFinished {turn_at - at:.0f} s after the result" if turn_at else "no turnFinished after the result")

    links = [entry for entry in timeline if entry.get("type") == "link"]
    before = [entry for entry in links if entry["t"] <= at]
    check("Mac away at the finish", bool(before) and before[-1].get("connected") == 0,
          f"{before[-1].get('connected')} devices connected" if before else "no connection record before the finish")
    last_end = turn_at or at
    reconnected = [entry for entry in links if entry["t"] > last_end and entry.get("connected", 0) > 0]
    # A connection before the wake would mean the Mac talked to the host while it was meant to be asleep.
    earliest = woke + clock["offset"] - clock.get("uncertainty", 0) - 1
    check("Mac back after the wake", bool(reconnected) and reconnected[0]["t"] >= earliest,
          f"reconnected {reconnected[0]['t'] - (woke + clock['offset']):+.0f} s from the wake" if reconnected
          else "never seen again")
    return results


def evidence(results: list, record: dict | None, timeline: list) -> str:
    starts = [entry for entry in timeline if entry.get("type") == "observer" and entry.get("event") == "start"]
    host = (starts[-1] if starts else {}).get("host") or {}
    lines = ["| Assertion | Result | Detail |", "| --- | --- | --- |"]
    for name, passed, detail in results:
        lines.append(f"| {name} | {'pass' if passed else 'FAIL'} | {detail} |")
    lines += ["", f"Host: build {host.get('build')}, version {host.get('version')}, {host.get('system')}, "
              f"keep awake {host.get('keepAwake')}, channel {host.get('channel')}."]
    if record:
        lines.append(f"Mac: instance {record.get('instance')}, build {record.get('build')}; clock offset "
                     f"{record['clock']['offset']:+.2f} s (droid minus Mac), give or take "
                     f"{record['clock']['uncertainty']:.2f} s.")
    return "\n".join(lines)


def verify(args) -> int:
    timeline = load_timeline(Path(args.timeline))
    record = json.loads(Path(args.operator).read_text()) if args.operator and Path(args.operator).exists() else None
    results = assess(timeline, record, args.fixture_run)
    print(evidence(results, record, timeline))
    return 0 if results and all(passed for _, passed, _ in results) else 1


def clock(_args) -> int:
    print(f"{time.time():.6f}")
    return 0


# MARK: - Entry


def parser() -> argparse.ArgumentParser:
    main = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    commands = main.add_subparsers(dest="command", required=True)

    def job(command, app=True):
        command.add_argument("--root", default="~/droid-walkaway", help="the job's folder")
        command.add_argument("--name", default="droid-walkaway", help="the build's .dev.<name> suffix")
        if app:
            command.add_argument("--app", default="~/droid-walkaway/dd/Build/Products/Debug/Native.app")

    made = commands.add_parser("fixture", help="make the fixture repository")
    job(made, app=False)
    made.add_argument("--before", type=int, default=2, help="steps before waiting for the Mac to go away")
    made.add_argument("--after", type=int, default=3, help="steps after it went away")
    made.add_argument("--step-seconds", type=int, default=60)
    made.add_argument("--no-hold", action="store_true", help="run every step without waiting for the gate")
    made.add_argument("--hold-poll", type=int, default=90, help="seconds one waiting step waits")
    made.add_argument("--hold-max", type=int, default=2700, help="seconds from the start before giving up")
    made.add_argument("--force", action="store_true")
    made.set_defaults(run=fixture)

    hosted = commands.add_parser("host", help="the job's development host")
    hosted.add_argument("action", choices=["start", "stop", "restart", "status"])
    job(hosted)
    hosted.set_defaults(run=host_command)

    prepared = commands.add_parser("setup", help="task worktrees and the fixture project on the host")
    job(prepared)
    prepared.set_defaults(run=setup)

    switched = commands.add_parser("gateway", help="stand-in: the host stops or starts taking paired devices")
    switched.add_argument("state", choices=["off", "on"])
    job(switched)
    switched.set_defaults(run=gateway)

    paired = commands.add_parser("pair", help="a single-use pairing link")
    job(paired)
    paired.add_argument("--json", action="store_true")
    paired.set_defaults(run=pair)

    watched = commands.add_parser("observe", help="record the host's side of the walk-away")
    job(watched)
    watched.add_argument("--every", type=float, default=5)
    watched.add_argument("--duration", type=float, default=4 * 3600, help="seconds before stopping by itself")
    watched.add_argument("--arm", action="store_true", help="open the fixture's gate once the Mac has gone away")
    watched.add_argument("--gate-after", type=float, default=60, help="seconds away before the gate opens")
    watched.set_defaults(run=observe)

    recorded = commands.add_parser("operator", help="the Mac's sleep record as the operator file")
    recorded.add_argument("--clock", action="append", required=True, help="mac-before,droid,mac-after (epoch s)")
    recorded.add_argument("--heartbeat", help="the Mac's heartbeat file: one epoch time per line")
    recorded.add_argument("--interval", type=float, default=5, help="seconds between heartbeats")
    recorded.add_argument("--kern-sleep", type=float, help="kern.sleeptime after the wake (epoch s)")
    recorded.add_argument("--kern-wake", type=float, help="kern.waketime after the wake (epoch s)")
    recorded.add_argument("--stand-in", help="what stood in for the sleep (a quit, a dropped connection)")
    recorded.add_argument("--away-from", type=float, help="with --stand-in: when the Mac went away (epoch s)")
    recorded.add_argument("--away-until", type=float, help="with --stand-in: when it came back (epoch s)")
    recorded.add_argument("--instance", default="droid-walkaway")
    recorded.add_argument("--build", required=True, help="the Mac instance's commit")
    recorded.add_argument("--output")
    recorded.set_defaults(run=operator)

    checked = commands.add_parser("verify", help="check a timeline against the operator file")
    checked.add_argument("--timeline", required=True)
    checked.add_argument("--operator")
    checked.add_argument("--fixture-run", help="the fixture run to check (default: the last that finished)")
    checked.set_defaults(run=verify)

    timed = commands.add_parser("clock", help="this machine's clock")
    timed.set_defaults(run=clock)
    return main


def main(argv=None) -> int:
    args = parser().parse_args(argv)
    try:
        return args.run(args)
    except Refused as error:
        print(f"refused: {error}", file=sys.stderr)
        return 3
    except (ValueError, OSError, RuntimeError) as error:
        print(f"droid-walkaway: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
