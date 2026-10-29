#!/usr/bin/env python3
"""Plan an automatic beta without creating a tag or publishing a release.

    python3 scripts/release/beta-schedule.py --dry-run

Read the fetched origin/main and version tags. CI also checks published releases and
active release runs, then writes the plan to GITHUB_OUTPUT; the workflow owns tagging and calls release.yml.
"""
import argparse
import json
import os
from pathlib import Path
import re
import subprocess
import sys


VERSION_TAG = re.compile(r"v(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)(?:-beta\.(0|[1-9][0-9]*))?")
RELEASE_WORKFLOWS = {
    ".github/workflows/release.yml",
    ".github/workflows/nightly.yml",
    ".github/workflows/beta.yml",
}


def command(*args):
    return subprocess.check_output(args, text=True).strip()


def active_release(repository, current_run):
    # Include queued and approval-waiting runs, even when newer runs have completed.
    for status in ("in_progress", "queued", "waiting", "pending", "requested"):
        pages = json.loads(command(
            "gh", "api", "--paginate", "--slurp",
            f"repos/{repository}/actions/runs?status={status}&per_page=100",
        ))
        for page in pages:
            for run in page["workflow_runs"]:
                if run["path"] in RELEASE_WORKFLOWS and str(run["id"]) != current_run:
                    return run["html_url"]
    return None


def published_release_tags(repository):
    pages = json.loads(command(
        "gh", "api", "--paginate", "--slurp",
        f"repos/{repository}/releases?per_page=100",
    ))
    return {release["tag_name"] for page in pages for release in page if not release["draft"]}


def plan_beta(published_tags=None):
    sha = command("git", "rev-parse", "--verify", "origin/main^{commit}")
    stable, beta = [], []
    for tag in command("git", "tag", "--list").splitlines():
        match = VERSION_TAG.fullmatch(tag)
        if match:
            core = tuple(int(value) for value in match.groups()[:3])
            if match[4]:
                beta.append(((*core, int(match[4])), tag))
            else:
                stable.append((core, tag))
    latest_stable = max(stable, default=None)
    latest_beta = max(beta, default=None)
    # Failed builds leave immutable tags behind. Reserve their numbers, but compare main and
    # generate notes from the last published release so those commits still reach users.
    published_beta = [entry for entry in beta if published_tags is None or entry[1] in published_tags]
    published_stable = [entry for entry in stable if published_tags is None or entry[1] in published_tags]
    previous = max(published_beta, default=None) or max(published_stable, default=None)
    notes_from = previous[1] if previous else ""
    if previous:
        if subprocess.run(
            ["git", "merge-base", "--is-ancestor", notes_from, sha], check=False,
        ).returncode != 0:
            raise ValueError(f"{notes_from} is not on origin/main; release tags must come from main")
        if command("git", "rev-list", "--count", f"{notes_from}..{sha}") == "0":
            return {"skip": "true", "reason": f"main has no commits since {notes_from}; nothing to publish."}
    if latest_stable and (not latest_beta or latest_stable[0] >= latest_beta[0][:3]):
        major, minor, _ = latest_stable[0]
        version = f"{major}.{minor + 1}.0-beta.1"
    elif latest_beta:
        major, minor, patch, number = latest_beta[0]
        version = f"{major}.{minor}.{patch}-beta.{number + 1}"
    else:
        version = "0.1.0-beta.1"
    return {"skip": "false", "version": version, "sha": sha, "notes_from": notes_from,
            "notes_from_start": str(previous is None).lower()}


def main():
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--dry-run", action="store_true", help="print what would ship; write no workflow outputs")
    parser.add_argument("--check-runs", action="store_true", help="also check GitHub for active release runs")
    parser.add_argument("--check-releases", action="store_true", help="use published GitHub releases as the checkpoint")
    parser.add_argument("--github-output", type=Path, help="write the plan for the calling workflow")
    args = parser.parse_args()
    try:
        published_tags = published_release_tags(os.environ["GITHUB_REPOSITORY"]) if args.check_releases else None
        plan = plan_beta(published_tags)
        if args.check_runs and plan["skip"] == "false":
            repository = os.environ["GITHUB_REPOSITORY"]
            busy = active_release(repository, os.environ.get("GITHUB_RUN_ID", ""))
            if busy:
                plan = {"skip": "true", "reason": f"A release run is already active ({busy}); nothing to publish."}
        if plan["skip"] == "true":
            print(plan["reason"])
        else:
            print(f"Would release v{plan['version']} from origin/main at {plan['sha']}.")
            print(f"Release notes: {plan['notes_from'] or 'the first commit'}..{plan['sha']}")
        if args.dry_run:
            print("Dry run: no tag, build or release was created.")
        elif args.github_output:
            with args.github_output.open("a") as output:
                for key, value in plan.items():
                    if key != "reason":
                        print(f"{key}={value}", file=output)
    except (KeyError, ValueError, subprocess.CalledProcessError) as error:
        print(f"beta-schedule: {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
