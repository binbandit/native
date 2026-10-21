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
    parser.add_argument("--run-number", type=int, required=True)
    parser.add_argument("--attempt", type=int, required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    result = metadata(args.base, args.nightly, args.run_number, args.attempt)
    args.output.write_text(json.dumps(result, indent=2) + "\n")
    print(f"Mobile changes: {result['changed']}; version {result['version']} ({result['build']}); {result['sha'][:7]}")


if __name__ == "__main__":
    main()
