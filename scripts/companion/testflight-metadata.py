#!/usr/bin/env python3
"""Select mobile changes and generate Apple's numeric versions without committing version bumps."""

import argparse
import datetime as dt
import json
from pathlib import Path
import subprocess


def git(*args):
    return subprocess.check_output(["git", *args], text=True).strip()


def mobile_paths():
    return [line for line in Path(__file__).with_name("testflight-paths.txt").read_text().splitlines()
            if line and not line.startswith("#")]


def has_changes(base, head):
    if not base or set(base) == {"0"}:
        return True
    result = subprocess.run(["git", "diff", "--quiet", base, head, "--", *mobile_paths()], check=False)
    if result.returncode not in (0, 1):
        raise RuntimeError("Could not compare mobile sources; refusing to silently skip a release")
    return result.returncode == 1


def is_publish_run(run):
    return (run.get("event") != "pull_request"
            and run.get("head_branch") == "main"
            and run.get("display_title") == "TestFlight publish")


def latest_publish_run(repository):
    page = 1
    while True:
        result = json.loads(subprocess.check_output([
            "gh", "api", f"repos/{repository}/actions/workflows/testflight.yml/runs?branch=main&per_page=100&page={page}"
        ], text=True))
        runs = result["workflow_runs"]
        candidates = [run["run_number"] for run in runs if is_publish_run(run)]
        if candidates:
            return max(candidates)
        if len(runs) < 100:
            return 0
        page += 1


def require_current_run(run_number, latest):
    if latest > run_number:
        raise ValueError(f"Run {run_number} was superseded by publishing run {latest}; dispatch a new main run instead")


def build_version(run_number, attempt):
    # Apple's build fields allow four digits, then two, then two. Reruns need a fresh number too.
    if not 1 <= run_number <= 999900 or not 1 <= attempt <= 99:
        raise ValueError("run number must be 1…999900 and attempt 1…99")
    return f"{(run_number - 1) // 100 + 1}.{(run_number - 1) % 100}.{attempt}"


def metadata(base, nightly, run_number, attempt, now=None):
    sha = git("rev-parse", "HEAD")
    when = (now or dt.datetime.now(dt.timezone.utc)) if nightly else dt.datetime.fromtimestamp(
        int(git("show", "-s", "--format=%ct", "HEAD")), dt.timezone.utc)
    version = f"{when.year}.{when.month}.{when.day}"
    build = build_version(run_number, attempt)
    kind = "Nightly" if nightly else "Main"
    return {
        "changed": has_changes(base, sha), "sha": sha, "version": version, "build": build,
        "notes": f"{kind} · {version} ({build}) · {sha[:7]}\n{git('show', '-s', '--format=%s', 'HEAD')}",
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--base", default="")
    parser.add_argument("--nightly", action="store_true")
    parser.add_argument("--select-only", action="store_true")
    parser.add_argument("--repository", help="Refuse superseded main publishing runs before allocating upload metadata")
    parser.add_argument("--run-number", type=int)
    parser.add_argument("--attempt", type=int)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    if args.select_only:
        result = {"changed": has_changes(args.base, "HEAD"), "sha": git("rev-parse", "HEAD")}
    else:
        if args.run_number is None or args.attempt is None:
            parser.error("upload metadata requires --run-number and --attempt")
        if args.repository:
            require_current_run(args.run_number, latest_publish_run(args.repository))
        result = metadata(args.base, args.nightly, args.run_number, args.attempt)
    args.output.write_text(json.dumps(result, indent=2) + "\n")
    print(f"Prepared TestFlight metadata for {result['sha'][:7]}")


if __name__ == "__main__":
    main()
