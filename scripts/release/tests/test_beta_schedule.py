"""Exercise the scheduler CLI with real Git histories, without a publishing credential."""

import importlib.util
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch


RELEASE = Path(__file__).resolve().parents[1]
SCRIPT = RELEASE / "beta-schedule.py"
spec = importlib.util.spec_from_file_location("beta_schedule", SCRIPT)
schedule = importlib.util.module_from_spec(spec)
spec.loader.exec_module(schedule)


class BetaScheduleTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory(prefix="beta-schedule-test-")
        self.root = Path(self.directory.name)
        self.git("init", "-q")
        self.git("config", "user.name", "Test")
        self.git("config", "user.email", "test@example.invalid")
        self.commit("feat: first feature")

    def tearDown(self):
        self.directory.cleanup()

    def git(self, *args):
        return subprocess.check_output(["git", "-C", str(self.root), *args], text=True).strip()

    def commit(self, subject="fix: next improvement"):
        self.git("-c", "commit.gpgsign=false", "commit", "--allow-empty", "-qm", subject)
        self.git("update-ref", "refs/remotes/origin/main", "HEAD")

    def run_plan(self, *args, check=True, releases=None):
        output = self.root / "outputs"
        output.unlink(missing_ok=True)
        env = dict(os.environ)
        if releases is not None:
            bin_dir = self.root / "bin"
            bin_dir.mkdir(exist_ok=True)
            gh = bin_dir / "gh"
            gh.write_text(f"#!{sys.executable}\nprint({json.dumps(json.dumps([releases]))})\n")
            gh.chmod(0o755)
            env["PATH"] = f"{bin_dir}{os.pathsep}{env['PATH']}"
            env["GITHUB_REPOSITORY"] = "test/repo"
        result = subprocess.run(
            [sys.executable, str(SCRIPT), "--github-output", str(output), *args],
            cwd=self.root, text=True, capture_output=True, check=check, env=env,
        )
        values = dict(line.split("=", 1) for line in output.read_text().splitlines()) if output.exists() else {}
        return values, result

    def test_first_beta_after_stable_starts_next_minor(self):
        self.git("tag", "v0.1.0")
        self.commit()
        plan, _ = self.run_plan()
        self.assertEqual(plan["version"], "0.2.0-beta.1")
        self.assertEqual(plan["notes_from"], "v0.1.0")
        self.assertEqual(plan["sha"], self.git("rev-parse", "origin/main"))

    def test_no_tags_bootstraps_first_minor(self):
        plan, _ = self.run_plan()
        self.assertEqual(plan["version"], "0.1.0-beta.1")
        self.assertEqual(plan["notes_from"], "")

    def test_beta_numbers_sort_numerically_and_ignore_other_tags(self):
        for tag in ("v1.5.0-beta.9", "v1.5.0-beta.10", "v1.5.0-beta.2", "nightly", "v99.0.0-rc.1"):
            self.git("tag", tag)
        self.commit()
        plan, _ = self.run_plan()
        self.assertEqual(plan["version"], "1.5.0-beta.11")
        self.assertEqual(plan["notes_from"], "v1.5.0-beta.10")

    def test_new_stable_starts_next_minor_but_notes_keep_previous_beta(self):
        self.git("tag", "v1.5.0-beta.3")
        self.commit("feat: added before stable")
        self.git("tag", "v1.5.0")
        self.commit()
        plan, _ = self.run_plan()
        self.assertEqual(plan["version"], "1.6.0-beta.1")
        self.assertEqual(plan["notes_from"], "v1.5.0-beta.3")

    def test_manual_beta_zero_continues_its_series(self):
        self.git("tag", "v1.6.0-beta.0")
        self.commit()
        plan, _ = self.run_plan()
        self.assertEqual(plan["version"], "1.6.0-beta.1")

    def test_stable_patch_does_not_reset_a_higher_beta_series(self):
        self.git("tag", "v1.5.0-beta.2")
        self.commit()
        self.git("tag", "v1.4.9")
        plan, _ = self.run_plan()
        self.assertEqual(plan["version"], "1.5.0-beta.3")

    def test_unchanged_main_skips_beta_and_first_beta(self):
        for tag in ("v0.1.0", "v0.2.0-beta.1"):
            with self.subTest(tag=tag):
                self.git("tag", tag)
                plan, result = self.run_plan()
                self.assertEqual(plan, {"skip": "true"})
                self.assertIn(f"main has no commits since {tag}", result.stdout)

    def test_annotated_tag_and_dispatched_branch_still_use_origin_main(self):
        self.git("-c", "tag.gpgsign=false", "tag", "-am", "beta", "v1.5.0-beta.1")
        self.commit()
        main = self.git("rev-parse", "HEAD")
        self.git("-c", "commit.gpgsign=false", "commit", "--allow-empty", "-qm", "feat: branch only")
        plan, _ = self.run_plan()
        self.assertEqual(plan["sha"], main)
        self.assertEqual(plan["version"], "1.5.0-beta.2")

    def test_unchanged_main_skips_without_needing_the_api(self):
        self.git("tag", "v1.5.0-beta.1")
        plan, result = self.run_plan("--check-runs")
        self.assertEqual(plan, {"skip": "true"})
        self.assertIn("nothing to publish", result.stdout)

    def test_beta_outside_main_fails_closed(self):
        main = self.git("rev-parse", "HEAD")
        self.commit()
        self.git("tag", "v1.5.0-beta.1")
        self.git("update-ref", "refs/remotes/origin/main", main)
        plan, result = self.run_plan(check=False)
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(plan, {})
        self.assertIn("is not on origin/main", result.stderr)

    def test_dry_run_prints_plan_and_writes_nothing(self):
        self.git("tag", "v0.1.0")
        self.commit()
        refs = self.git("show-ref")
        plan, result = self.run_plan("--dry-run")
        self.assertEqual(plan, {})
        self.assertIn("Would release v0.2.0-beta.1", result.stdout)
        self.assertIn("no tag, build or release was created", result.stdout)
        self.assertEqual(self.git("show-ref"), refs)
        self.assertEqual(self.git("status", "--porcelain"), "")

    def test_failed_tags_do_not_skip_unpublished_main_or_omit_release_notes(self):
        self.git("tag", "v0.2.0-beta.18")
        self.commit("fix: failed beta 19")
        self.git("tag", "v0.2.0-beta.19")
        self.commit("fix: failed beta 20")
        self.git("tag", "v0.2.0-beta.20")
        refs = self.git("show-ref")
        plan, _ = self.run_plan("--check-releases", releases=[
            {"tag_name": "v0.2.0-beta.18", "draft": False},
            {"tag_name": "v0.2.0-beta.20", "draft": True},
        ])
        self.assertEqual(plan["skip"], "false")
        self.assertEqual(plan["version"], "0.2.0-beta.21")
        self.assertEqual(plan["notes_from"], "v0.2.0-beta.18")
        self.assertEqual(plan["sha"], self.git("rev-parse", "origin/main"))
        self.assertEqual(self.git("show-ref"), refs)

    def test_published_main_still_skips(self):
        self.git("tag", "v0.2.0-beta.20")
        plan, _ = self.run_plan("--check-releases", releases=[
            {"tag_name": "v0.2.0-beta.20", "draft": False},
        ])
        self.assertEqual(plan, {"skip": "true"})

    def test_first_published_beta_uses_stable_notes_and_reserves_failed_numbers(self):
        self.git("tag", "v0.1.0")
        self.commit()
        self.git("tag", "v0.2.0-beta.1")
        plan, _ = self.run_plan("--check-releases", releases=[
            {"tag_name": "v0.1.0", "draft": False},
        ])
        self.assertEqual(plan["version"], "0.2.0-beta.2")
        self.assertEqual(plan["notes_from"], "v0.1.0")

    def test_only_unpublished_tags_still_plan_a_release(self):
        self.git("tag", "v0.2.0-beta.20")
        plan, _ = self.run_plan("--check-releases", releases=[])
        self.assertEqual(plan["version"], "0.2.0-beta.21")
        self.assertEqual(plan["notes_from"], "")

    def test_no_published_release_preserves_whole_history_in_notes_consumer(self):
        self.git("tag", "v0.2.0-beta.19")
        self.commit("fix: before failed beta 20")
        self.git("tag", "v0.2.0-beta.20")
        self.commit("fix: after failed beta 20")
        plan, _ = self.run_plan("--check-releases", releases=[])
        selection = (RELEASE / "release.sh").read_text().split('previous_tag=""\n', 1)[1].split('\nnotes=', 1)[0]
        script = 'sha=$(git rev-parse HEAD)\nchannel=beta\n' + selection
        script += '\nprintf "%s" "$previous_tag"'
        for explicit, expected in ((plan["notes_from_start"], ""), ("false", "v0.2.0-beta.20")):
            previous = subprocess.check_output(
                ["bash", "-eu", "-c", script], cwd=self.root, text=True,
                env={**os.environ, "NATIVE_RELEASE_NOTES_FROM": plan["notes_from"],
                     "NATIVE_RELEASE_NOTES_FROM_START": explicit},
            )
            self.assertEqual(previous, expected)
            notes = subprocess.check_output(
                ["bash", str(RELEASE / "release-notes.sh"), previous, "HEAD"], cwd=self.root, text=True,
            )
            self.assertEqual("first feature" in notes, explicit == "true")
            self.assertEqual("before failed beta 20" in notes, explicit == "true")
            self.assertIn("after failed beta 20", notes)

    def test_release_aware_dry_run_writes_no_outputs(self):
        self.git("tag", "v0.2.0-beta.20")
        plan, result = self.run_plan("--check-releases", "--dry-run", releases=[])
        self.assertEqual(plan, {})
        self.assertIn("Would release v0.2.0-beta.21", result.stdout)

    def test_beta_notes_override_includes_commits_before_intervening_stable(self):
        self.git("tag", "v1.5.0-beta.1")
        self.commit("feat: before stable")
        self.git("tag", "v1.5.0")
        self.commit("fix: after stable")
        # Execute the actual notes selection used by release.sh, without its build/upload steps.
        selection = (RELEASE / "release.sh").read_text().split('previous_tag=""\n', 1)[1].split('\nnotes=', 1)[0]
        script = 'sha=$(git rev-parse HEAD)\nchannel=beta\n' + selection
        script += '\nprintf "%s" "$previous_tag"'
        for override, expected in (("", "v1.5.0"), ("v1.5.0-beta.1", "v1.5.0-beta.1")):
            previous = subprocess.check_output(
                ["bash", "-eu", "-c", script], cwd=self.root, text=True,
                env={**os.environ, "NATIVE_RELEASE_NOTES_FROM": override},
            )
            self.assertEqual(previous, expected)
            notes = subprocess.check_output(
                ["bash", str(RELEASE / "release-notes.sh"), previous, "HEAD"], cwd=self.root, text=True,
            )
            self.assertEqual("before stable" in notes, bool(override))
            self.assertIn("after stable", notes)

    def test_published_releases_read_all_pages_and_ignore_drafts(self):
        pages = [[{"tag_name": "v1.5.0-beta.20", "draft": True}], [
            {"tag_name": "v1.5.0-beta.18", "draft": False},
            {"tag_name": "v1.4.0", "draft": False},
        ]]
        with patch.object(schedule, "command", return_value=json.dumps(pages)) as api:
            self.assertEqual(schedule.published_release_tags("test/repo"), {"v1.5.0-beta.18", "v1.4.0"})
            self.assertIn("--paginate", api.call_args.args)
        with patch.object(schedule, "command", side_effect=subprocess.CalledProcessError(1, "gh")):
            with self.assertRaises(subprocess.CalledProcessError):
                schedule.published_release_tags("test/repo")

    def test_busy_release_in_each_active_state_and_each_mac_workflow(self):
        for status in ("in_progress", "queued", "waiting", "pending", "requested"):
            for workflow in schedule.RELEASE_WORKFLOWS:
                with self.subTest(status=status, workflow=workflow):
                    def response(*args):
                        runs = [{"path": workflow, "id": 10, "html_url": "https://example.invalid/run/10"}]
                        return json.dumps([{"workflow_runs": runs if f"status={status}&" in args[-1] else []}])
                    with patch.object(schedule, "command", side_effect=response):
                        self.assertEqual(schedule.active_release("test/repo", "20"), "https://example.invalid/run/10")

    def test_active_run_check_ignores_itself_and_unrelated_workflows(self):
        pages = [{"workflow_runs": [
            {"path": ".github/workflows/beta.yml", "id": 20},
            {"path": ".github/workflows/ci.yml", "id": 30},
        ]}]
        with patch.object(schedule, "command", return_value=json.dumps(pages)):
            self.assertIsNone(schedule.active_release("test/repo", "20"))

    def test_active_run_check_reads_later_pages_and_fails_on_api_errors(self):
        pages = [{"workflow_runs": []}, {"workflow_runs": [
            {"path": ".github/workflows/release.yml", "id": 10, "html_url": "https://example.invalid/run/10"},
        ]}]
        with patch.object(schedule, "command", return_value=json.dumps(pages)):
            self.assertEqual(schedule.active_release("test/repo", "20"), "https://example.invalid/run/10")
        with patch.object(schedule, "command", side_effect=subprocess.CalledProcessError(1, "gh")):
            with self.assertRaises(subprocess.CalledProcessError):
                schedule.active_release("test/repo", "20")


if __name__ == "__main__":
    unittest.main()
