"""Offline tests for droid-walkaway.py: fabricated builds, timelines and a fake host, no machines."""

import importlib.util
import json
import os
import plistlib
import socketserver
import subprocess
import tempfile
import threading
import unittest
from pathlib import Path
from unittest import mock

spec = importlib.util.spec_from_file_location("droid_walkaway", Path(__file__).parent / "droid-walkaway.py")
walkaway = importlib.util.module_from_spec(spec)
spec.loader.exec_module(walkaway)

CHANNEL = "0123456789"
LABEL = f"dev.binbandit.native.dev.droid-walkaway.host.{CHANNEL}"


def make_app(folder: Path, identifier="dev.binbandit.native.dev.droid-walkaway", label=LABEL, channel=CHANNEL,
             development="1") -> Path:
    app = folder / "Native.app"
    (app / "Contents/Library/LaunchAgents").mkdir(parents=True)
    with open(app / "Contents/Info.plist", "wb") as file:
        plistlib.dump({"CFBundleIdentifier": identifier}, file)
    with open(app / "Contents/Library/LaunchAgents/NativeHost.plist", "wb") as file:
        plistlib.dump({
            "Label": label,
            "BundleProgram": "Contents/Library/LoginItems/Native Host.app/Contents/MacOS/Native Host",
            "EnvironmentVariables": {"NATIVE_HOST_CHANNEL": channel, "NATIVE_HOST_DEVELOPMENT": development},
        }, file)
    return app


class HomeTestCase(unittest.TestCase):
    """A fake home folder under /tmp, short enough for Unix socket paths."""

    def setUp(self):
        self.home = Path(tempfile.mkdtemp(dir="/tmp", prefix="dw")).resolve()
        self.addCleanup(subprocess.run, ["rm", "-rf", str(self.home)])
        patcher = mock.patch.dict(os.environ, {"HOME": str(self.home)})
        patcher.start()
        self.addCleanup(patcher.stop)


class TargetTests(HomeTestCase):
    def test_accepts_the_jobs_development_build(self):
        app = make_app(self.home / "droid-walkaway/dd")
        host = walkaway.dev_host(app, "droid-walkaway")
        self.assertEqual(host.label, LABEL)
        self.assertEqual(host.directory, self.home / "Library/Application Support/Native/Channels" / CHANNEL)

    def test_refuses_the_installed_app(self):
        app = make_app(self.home / "Applications")
        with self.assertRaisesRegex(walkaway.Refused, "installed Native"):
            walkaway.dev_host(app, "droid-walkaway")

    def test_refuses_another_bundle_id(self):
        app = make_app(self.home / "x", identifier="dev.binbandit.native", label=f"dev.binbandit.native.host.{CHANNEL}")
        with self.assertRaisesRegex(walkaway.Refused, "not droid-walkaway's development build"):
            walkaway.dev_host(app, "droid-walkaway")

    def test_refuses_a_host_without_a_development_channel(self):
        for channel, development in (("nightly", "1"), ("", "1"), (CHANNEL, "")):
            with self.subTest(channel=channel, development=development):
                app = make_app(Path(tempfile.mkdtemp(dir=self.home)), channel=channel, development=development)
                with self.assertRaisesRegex(walkaway.Refused, "development channel"):
                    walkaway.dev_host(app, "droid-walkaway")

    def test_refuses_a_label_that_is_not_the_builds_own(self):
        app = make_app(self.home / "x", label="dev.binbandit.native.host")
        with self.assertRaisesRegex(walkaway.Refused, "development host label"):
            walkaway.dev_host(app, "droid-walkaway")

    def test_job_folder_stays_out_of_installed_apps_data(self):
        self.assertEqual(walkaway.job_root(str(self.home / "droid-walkaway")), self.home / "droid-walkaway")
        for path in (self.home, self.home / "Library/Application Support/Native", self.home / ".native/x", "/tmp/x"):
            with self.subTest(path=path), self.assertRaises(walkaway.Refused):
                walkaway.job_root(str(path))


class ClockTests(unittest.TestCase):
    def test_offset_comes_from_the_shortest_round_trip(self):
        offset, uncertainty = walkaway.clock_offset([(100.0, 103.0, 101.0), (200.0, 202.6, 200.2)])
        self.assertAlmostEqual(offset, 2.5)
        self.assertAlmostEqual(uncertainty, 0.1)

    def test_no_samples_is_an_error(self):
        with self.assertRaises(ValueError):
            walkaway.clock_offset([])

    def test_sleep_window_is_the_longest_gap_bounded_inward(self):
        beats = [0, 5, 10, 15, 1015, 1020]
        self.assertEqual(walkaway.sleep_window(beats, 5), (20, 1010))

    def operator_record(self, *options):
        with tempfile.TemporaryDirectory() as folder:
            beats, output = Path(folder) / "beats", Path(folder) / "operator.json"
            beats.write_text("\n".join(str(beat) for beat in (0, 5, 10, 15, 1015, 1020)))
            with mock.patch("sys.stdout"):
                walkaway.main(["operator", "--clock", "0,0,0.2", "--build", "abc", "--heartbeat", str(beats),
                               "--output", str(output), *options])
            return json.loads(output.read_text())

    def test_the_kernels_times_sharpen_the_heartbeats_gap(self):
        record = self.operator_record("--kern-sleep", "17", "--kern-wake", "1013")
        self.assertEqual((record["sleptAt"], record["wokeAt"]), (17, 1013))
        self.assertEqual(record["sources"], ["heartbeat", "kern.sleeptime/kern.waketime"])

    def test_the_kernels_times_from_another_sleep_are_left_out(self):
        record = self.operator_record("--kern-sleep", "1030", "--kern-wake", "1040")
        self.assertEqual((record["sleptAt"], record["wokeAt"]), (20, 1010))
        self.assertEqual(record["sources"], ["heartbeat"])
        self.assertIn("notes", record)

    def test_a_heartbeat_without_a_gap_means_no_sleep(self):
        with self.assertRaisesRegex(ValueError, "never slept"):
            walkaway.sleep_window([0, 5, 10, 15, 20], 5)


class GateTests(unittest.TestCase):
    def test_opens_only_after_the_mac_was_seen_and_then_stayed_away(self):
        self.assertFalse(walkaway.gate_should_open([(0, False), (100, False)], 100, 60))
        samples = [(0, True), (10, False), (40, False)]
        self.assertFalse(walkaway.gate_should_open(samples, 40, 60))
        self.assertTrue(walkaway.gate_should_open(samples + [(70, False)], 70, 60))

    def test_a_reconnection_starts_the_wait_again(self):
        samples = [(0, True), (10, False), (50, True), (60, False)]
        self.assertFalse(walkaway.gate_should_open(samples, 100, 60))
        self.assertTrue(walkaway.gate_should_open(samples, 120, 60))


def timeline(finish=1500.0, turn=1504.0, label=LABEL, connected_at_finish=False, back=2105.0):
    """A walk-away as the droid records it: the Mac sleeps 1000-2100 by its clock, 2 s behind."""
    records = [
        {"t": 0, "type": "observer", "event": "start",
         "host": {"label": label, "channel": CHANNEL, "channelReported": CHANNEL, "build": "1"}},
        {"t": 1, "type": "link", "paired": 1, "connected": 1},
        {"t": 900, "type": "mark", "at": 900, "run": "r1", "event": "start"},
        {"t": 960, "type": "mark", "at": 960, "run": "r1", "event": "step", "step": 1},
        {"t": 1030, "type": "link", "paired": 1, "connected": 0},
        {"t": 1100, "type": "mark", "at": 1100, "run": "r1", "event": "hold", "step": 2},
        {"t": 1300, "type": "mark", "at": 1300, "run": "r1", "event": "step", "step": 3},
    ]
    if connected_at_finish:
        records.append({"t": finish - 10, "type": "link", "paired": 1, "connected": 1})
    records += [
        {"t": finish, "type": "mark", "at": finish, "run": "r1", "event": "done", "result": "pass"},
        {"t": turn, "type": "activity", "at": turn, "kind": "turnFinished", "session": "s1"},
        {"t": back, "type": "link", "paired": 1, "connected": 1},
    ]
    return sorted(records, key=lambda record: record["t"])


OPERATOR = {"sleptAt": 998.0, "wokeAt": 2098.0, "sources": ["heartbeat"], "instance": "droid-walkaway",
            "build": "abc", "clock": {"offset": 2.0, "uncertainty": 0.5, "samples": 3}}


class VerdictTests(unittest.TestCase):
    def verdict(self, records, operator=OPERATOR):
        return {name: passed for name, passed, _ in walkaway.assess(records, operator)}

    def test_a_finish_while_asleep_passes_every_assertion(self):
        results = self.verdict(timeline())
        self.assertTrue(all(results.values()), results)
        self.assertIn("finished while asleep", results)

    def test_refuses_a_finish_before_the_sleep(self):
        records = [record for record in timeline(finish=995, turn=996) if record.get("event") != "hold"
                   and record.get("step") != 3]
        self.assertFalse(self.verdict(records)["finished while asleep"])

    def test_refuses_a_finish_after_the_wake(self):
        results = self.verdict(timeline(finish=2101, turn=2103, back=2200))
        self.assertFalse(results["finished while asleep"])
        self.assertFalse(results["turn ended while asleep"])

    def test_refuses_a_finish_inside_the_clock_margin(self):
        # The sleep starts at 1000 on the droid's clock, give or take 1.5 s.
        records = [record for record in timeline(finish=1001, turn=1300) if record.get("at", 0) <= 1001
                   or record.get("type") != "mark"]
        self.assertFalse(self.verdict(records)["finished while asleep"])

    def test_refuses_without_the_operator_record(self):
        results = walkaway.assess(timeline(), None)
        self.assertIn(("operator record", False), [(name, passed) for name, passed, _ in results])
        self.assertFalse(all(passed for _, passed, _ in results))

    def test_refuses_an_operator_record_that_ends_before_it_starts(self):
        broken = dict(OPERATOR, wokeAt=900.0)
        self.assertFalse(self.verdict(timeline(), broken)["operator record"])

    def test_a_stand_in_rehearses_but_never_passes(self):
        results = self.verdict(timeline(), dict(OPERATOR, sources=["stand-in: app quit"]))
        self.assertFalse(results.pop("real sleep"))
        self.assertTrue(all(results.values()), results)

    def test_operator_file_labels_a_stand_in(self):
        with tempfile.TemporaryDirectory() as folder:
            output = Path(folder) / "operator.json"
            arguments = ["operator", "--clock", "10,12.5,11", "--build", "abc", "--output", str(output)]
            with mock.patch("sys.stdout"):
                self.assertEqual(walkaway.main(arguments + ["--stand-in", "app quit", "--away-from", "20",
                                                            "--away-until", "90"]), 0)
                record = json.loads(output.read_text())
                self.assertEqual(record["sources"], ["stand-in: app quit"])
                self.assertEqual((record["sleptAt"], record["wokeAt"]), (20, 90))
                self.assertAlmostEqual(record["clock"]["offset"], 2.0)
                with mock.patch("sys.stderr"):
                    self.assertEqual(walkaway.main(arguments), 1)

    def test_refuses_a_timeline_from_the_installed_host(self):
        results = self.verdict(timeline(label="dev.binbandit.native.host"))
        self.assertFalse(results["development host"])

    def test_refuses_when_the_mac_was_connected_at_the_finish(self):
        self.assertFalse(self.verdict(timeline(connected_at_finish=True))["Mac away at the finish"])

    def test_refuses_a_reconnection_before_the_wake(self):
        self.assertFalse(self.verdict(timeline(back=1800))["Mac back after the wake"])

    def test_the_verdict_command_passes_a_real_sleep(self):
        with tempfile.TemporaryDirectory() as folder:
            path, operator = Path(folder) / "timeline.ndjson", Path(folder) / "operator.json"
            path.write_text("".join(json.dumps(record) + "\n" for record in timeline()))
            operator.write_text(json.dumps(OPERATOR))
            with mock.patch("sys.stdout"):
                self.assertEqual(walkaway.main(["verify", "--timeline", str(path), "--operator", str(operator)]), 0)
                self.assertEqual(walkaway.main(["verify", "--timeline", str(path), "--operator", str(operator),
                                                "--fixture-run", "another"]), 1)

    def test_the_verdict_command_fails_without_the_operator_file(self):
        with tempfile.TemporaryDirectory() as folder:
            path = Path(folder) / "timeline.ndjson"
            path.write_text("".join(json.dumps(record) + "\n" for record in timeline()))
            with mock.patch("sys.stdout"):
                self.assertEqual(walkaway.main(["verify", "--timeline", str(path)]), 1)
                self.assertEqual(
                    walkaway.main(["verify", "--timeline", str(path), "--operator", str(Path(folder) / "none")]), 1)


class FixtureTests(HomeTestCase):
    def make(self, *options):
        with mock.patch("sys.stdout"):
            self.assertEqual(walkaway.main(["fixture", "--root", str(self.home / "job"), *options]), 0)
        return self.home / "job/fixture"

    def step(self, folder):
        return subprocess.run([str(folder / "walkaway"), "next"], cwd=folder, capture_output=True, text=True,
                              check=True).stdout

    def marks(self):
        lines = (self.home / "job/evidence/marks.ndjson").read_text().splitlines()
        return [json.loads(line)["event"] for line in lines]

    def test_runs_every_step_then_writes_and_tests_its_result(self):
        folder = self.make("--before", "1", "--after", "1", "--step-seconds", "0", "--no-hold")
        self.assertIn("Step 1 of 2", self.step(folder))
        self.assertIn("WALKAWAY-DONE result=pass steps=2", self.step(folder))
        self.assertIn("WALKAWAY-DONE result=pass", self.step(folder))
        self.assertEqual(self.marks(), ["start", "step", "step", "done"])
        self.assertIn("result=pass", (folder / "walkaway-result.txt").read_text())
        remote = subprocess.run(["git", "-C", str(folder), "remote", "-v"], capture_output=True, text=True).stdout
        self.assertIn(walkaway.FIXTURE_ORIGIN, remote)
        self.assertIn("no-push (push)", remote)

    def test_holds_until_the_gate_opens(self):
        folder = self.make("--before", "1", "--after", "1", "--step-seconds", "0", "--hold-poll", "0")
        self.step(folder)
        self.assertIn("Still waiting", self.step(folder))
        (self.home / "job/evidence/gate-open").write_text("1\n")
        self.assertIn("WALKAWAY-DONE result=pass", self.step(folder))
        self.assertEqual(self.marks(), ["start", "step", "hold", "step", "done"])

    def test_gives_up_when_the_gate_never_opens(self):
        folder = self.make("--before", "0", "--after", "1", "--step-seconds", "0", "--hold-poll", "0",
                           "--hold-max", "0")
        self.step(folder)
        self.assertIn("WALKAWAY-DONE result=gate-timeout", self.step(folder))


class FakeHost(socketserver.ThreadingMixIn, socketserver.UnixStreamServer):
    daemon_threads = True

    def __init__(self, path, answers):
        self.answers = answers
        super().__init__(str(path), FakeHandler)


class FakeHandler(socketserver.StreamRequestHandler):
    def handle(self):
        for line in self.rfile:
            request = json.loads(line)
            answer = self.server.answers(request["method"])
            self.wfile.write(json.dumps({"jsonrpc": "2.0", "method": "_native/noise", "params": {}}).encode() + b"\n")
            self.wfile.write(json.dumps({"jsonrpc": "2.0", "id": request["id"], "result": answer}).encode() + b"\n")


class ObserverTests(HomeTestCase):
    def test_records_the_host_and_opens_the_gate_once_the_mac_is_away(self):
        host = walkaway.dev_host(make_app(self.home / "job/dd"), "droid-walkaway")
        host.link_socket_path.parent.mkdir(parents=True)
        # The Mac answers the first three status reads, then goes away.
        reads = {"count": 0}

        def link_status(method):
            reads["count"] += 1
            return {"isEnabled": True,
                    "devices": [{"device": {"id": "d1", "name": "Someone's Mac"}, "isConnected": reads["count"] <= 3}]}

        link = FakeHost(host.link_socket_path, link_status)
        answers = {
            "initialize": {"hostID": "h1", "channel": CHANNEL, "epoch": "e1", "processID": 7,
                           "hostInfo": {"version": "1.0", "build": "42"}},
            "_native/host/status": {"system": "macOS 27.0", "keepAwake": {"policy": {"mode": "off"}}},
            "_native/host/doctor": {"checks": [{"id": "claude", "status": "ok", "detail": "/private/path"}]},
            "session/list": [{"id": "s1", "agentID": "claude-code", "phase": "prompting", "cwd": "/secret/path",
                              "title": "A private title", "titles": {"generated": "A private title"}}],
            "_native/activity/list": [{"id": 3, "at": 1000, "kind": "turnFinished", "sessionID": "s1",
                                       "subject": "A private title"}],
            "_native/notifications/list": {"notifications": [], "active": []},
        }
        server = FakeHost(host.socket_path, lambda method: answers[method])
        for running in (link, server):
            threading.Thread(target=running.serve_forever, daemon=True).start()
            self.addCleanup(running.server_close)
            self.addCleanup(running.shutdown)
        root = self.home / "job"
        args = mock.Mock(arm=True, gate_after=0.2, every=0.05, duration=1.5)
        walkaway.Observer(host, root, args).run()

        text = (root / "evidence/timeline.ndjson").read_text()
        records = [json.loads(line) for line in text.splitlines()]
        kinds = [record["type"] for record in records]
        self.assertEqual(records[0]["host"]["tools"], {"claude": "ok"})
        self.assertIn("gate", kinds)
        self.assertTrue((root / "evidence/gate-open").exists())
        self.assertEqual([record["connected"] for record in records if record["type"] == "link"], [1, 0])
        session = next(record for record in records if record["type"] == "session")
        self.assertEqual(session["title"], "generated")
        for private in ("/secret/path", "A private title", "Someone's Mac", "/private/path"):
            self.assertNotIn(private, text)


if __name__ == "__main__":
    unittest.main()
