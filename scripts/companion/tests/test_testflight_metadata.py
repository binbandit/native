"""Exercise actual Git diffs, including changes the mobile pipeline must skip."""

import datetime as dt
import json
import sys
import importlib.util
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest.mock import patch

spec = importlib.util.spec_from_file_location(
    "metadata", Path(__file__).resolve().parents[1] / "testflight-metadata.py")
metadata = importlib.util.module_from_spec(spec)
spec.loader.exec_module(metadata)


class TestFlightMetadataTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.root = Path(self.directory.name)
        self.git("init", "-q")
        self.git("config", "user.name", "Test")
        self.git("config", "user.email", "test@example.invalid")
        self.commit("Companion/NativeCompanion/App.swift")
        self.base = self.git("rev-parse", "HEAD")

    def tearDown(self):
        self.directory.cleanup()

    def git(self, *args):
        return subprocess.check_output(["git", "-C", str(self.root), *args], text=True).strip()

    def commit(self, name):
        path = self.root / name
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(str(len(self.git("log", "--oneline"))) if (self.root / "seed").exists() else "source")
        self.git("add", "--", name)
        self.git("commit", "-qm", f"change {name}")
        (self.root / "seed").touch()

    def changed(self):
        # The script uses Git's current directory in production; give it the fixture repository.
        original_run = subprocess.run
        with patch.object(metadata.subprocess, "run", side_effect=lambda *a, **kw: original_run(
                *a, cwd=self.root, **kw)):
            return metadata.has_changes(self.base, "HEAD")

    def test_mac_only_commit_does_not_upload(self):
        self.commit("native/Settings/Settings.swift")
        self.assertFalse(self.changed())

    def test_mobile_app_and_shared_sources_upload(self):
        for path in ["Companion/NativeCompanion/Settings/Settings.swift",
                     "Packages/NativeHost/Sources/NativeHostClient/Client.swift",
                     "Packages/Exec/Sources/Exec/Exec.swift",
                     "native/Views/Transcript/MarkdownView.swift",
                     "design/app-icon/celebrations/halloween/stable.icon/icon.json"]:
            with self.subTest(path=path):
                self.base = self.git("rev-parse", "HEAD")
                self.commit(path)
                self.assertTrue(self.changed())

    def test_host_implementation_tests_and_docs_do_not_upload(self):
        for path in ["Packages/NativeHost/Sources/NativeHost/Host.swift",
                     "Packages/ACP/Tests/ACPTests/Test.swift", "docs/companion.md",
                     "Companion/NativeCompanionUITests/Test.swift", "native/DesignSystem/README.md"]:
            self.commit(path)
        self.assertFalse(self.changed())

    def test_revert_and_deleted_shared_file_upload(self):
        self.git("rm", "Companion/NativeCompanion/App.swift")
        self.git("commit", "-qm", "remove mobile file")
        self.assertTrue(self.changed())
        removed = self.git("rev-parse", "HEAD")
        self.git("revert", "--no-edit", "HEAD")
        self.base = removed
        self.assertTrue(self.changed())

    def test_mac_merge_after_cancelled_mobile_run_keeps_mobile_change(self):
        self.commit("Companion/NativeCompanion/Task/Task.swift")
        self.commit("native/Settings/Settings.swift")
        self.assertTrue(self.changed())

    def test_unchanged_nightly_skips(self):
        self.assertFalse(self.changed())

    def test_missing_baseline_bootstraps_but_invalid_baseline_fails(self):
        self.assertTrue(metadata.has_changes("", "HEAD"))
        self.assertTrue(metadata.has_changes("0" * 40, "HEAD"))
        with self.assertRaises(RuntimeError):
            metadata.has_changes("missing-ref", "HEAD")

    def test_unique_monotonic_apple_build_numbers_including_reruns(self):
        numbers = [metadata.build_version(run, attempt) for run, attempt in
                   [(1, 1), (1, 2), (99, 1), (100, 1), (101, 1), (999900, 99)]]
        components = [tuple(map(int, number.split("."))) for number in numbers]
        self.assertEqual(sorted(set(components)), components)
        self.assertEqual(numbers[-1], "9999.99.99")
        for run, attempt in [(0, 1), (999901, 1), (1, 100)]:
            with self.assertRaises(ValueError):
                metadata.build_version(run, attempt)

    def test_upload_only_retry_allocates_fresh_metadata(self):
        # The source-selection job's outputs remain from attempt 1. Only this CLI runs again.
        script = Path(metadata.__file__).resolve()
        selection = self.root / "selection.json"
        subprocess.run([sys.executable, str(script), "--select-only", "--output", str(selection)],
                       cwd=self.root, check=True, capture_output=True)
        self.assertNotIn("build", json.loads(selection.read_text()))
        results = []
        for attempt in (1, 2):
            output = self.root / f"attempt-{attempt}.json"
            subprocess.run([sys.executable, str(script), "--run-number", "101", "--attempt", str(attempt),
                            "--output", str(output)], cwd=self.root, check=True, capture_output=True)
            results.append(json.loads(output.read_text()))
        self.assertEqual(results[0]["sha"], results[1]["sha"])
        self.assertNotEqual(results[0]["build"], results[1]["build"])
        self.assertIn(results[1]["build"], results[1]["notes"])

    def test_older_run_retry_is_refused_after_newer_publication(self):
        self.assertLess(metadata.build_version(101, 2), metadata.build_version(102, 1))
        with self.assertRaisesRegex(ValueError, "superseded"):
            metadata.require_current_run(101, 102)
        metadata.require_current_run(102, 102)

    def test_rehearsals_and_pull_requests_do_not_supersede_publication(self):
        self.assertTrue(metadata.is_publish_run({"head_branch": "main", "event": "push",
                                                "display_title": "TestFlight publish"}))
        self.assertFalse(metadata.is_publish_run({"head_branch": "main", "event": "workflow_dispatch",
                                                 "display_title": "TestFlight rehearsal"}))
        self.assertFalse(metadata.is_publish_run({"head_branch": "main", "event": "pull_request",
                                                 "display_title": "TestFlight publish"}))

    def test_latest_publication_lookup_paginates_past_rehearsals(self):
        rehearsal = {"head_branch": "main", "event": "workflow_dispatch",
                     "display_title": "TestFlight rehearsal", "run_number": 103}
        publish = {"head_branch": "main", "event": "push", "display_title": "TestFlight publish", "run_number": 102}
        with patch.object(metadata.subprocess, "check_output", side_effect=[
                json.dumps({"workflow_runs": [rehearsal] * 100}),
                json.dumps({"workflow_runs": [publish]})]) as query:
            self.assertEqual(metadata.latest_publish_run("example/repo"), 102)
            self.assertIn("page=2", query.call_args.args[0][-1])

    def test_daily_version_and_sha_notes(self):
        now = dt.datetime(2026, 10, 21, tzinfo=dt.timezone.utc)
        with patch.object(metadata, "git", side_effect=lambda *args: self.git(*args)):
            result = metadata.metadata("", True, 42, 1, now=now)
        self.assertEqual(result["version"], "2026.10.21")
        self.assertIn(self.base[:7], result["notes"])
        self.assertIn("Nightly", result["notes"])


if __name__ == "__main__":
    unittest.main()
