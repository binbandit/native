#!/usr/bin/env python3
"""Relocate SwiftPM workspace state and Git administrative paths in a private package clone."""
import json
from pathlib import Path
import sys
import subprocess


def relocate(value, mappings):
    if isinstance(value, dict):
        return {key: relocate(item, mappings) for key, item in value.items()}
    if isinstance(value, list):
        return [relocate(item, mappings) for item in value]
    if isinstance(value, str):
        for old, new in mappings:
            if value == old or value.startswith(old + "/"):
                return new + value[len(old):]
    return value


def relocate_packages(packages, old_repo, old_packages, new_repo, new_packages):
    mappings = [(old_packages, new_packages), (old_repo, new_repo)]
    state = packages / "workspace-state.json"
    if state.is_file():
        state.write_text(json.dumps(relocate(json.loads(state.read_text()), mappings), indent=2) + "\n")
    # SwiftPM uses shared Git clones: alternates and origin URLs point at its repositories folder.
    # Submodule gitdir/worktree pointers can also be absolute. Never rewrite source files or objects.
    for path in packages.rglob("*"):
        if path.is_symlink() or not path.is_file():
            continue
        administrative = ".git" in path.parts or path.relative_to(packages).parts[0] == "repositories"
        if path.name != ".git" and not (administrative and path.name in {"config", "alternates", "commondir"}):
            continue
        text = path.read_text()
        for old, new in mappings:
            text = text.replace(old + "/", new + "/")
        # Checkouts may be read-only. This is our APFS clone, never the publishing instance's inode.
        path.chmod(path.stat().st_mode | 0o200)
        path.write_text(text)


def validate_revisions(packages, resolved):
    """Workspace state is only a record: check the copied Git HEADs against the actual pins."""
    pins = {pin["identity"]: pin["state"]["revision"]
            for pin in json.loads(resolved.read_text())["pins"]
            if pin["kind"] in {"remoteSourceControl", "localSourceControl"}}
    dependencies = json.loads((packages / "workspace-state.json").read_text())["object"]["dependencies"]
    checked = set()
    for dependency in dependencies:
        state = dependency["state"]
        if "checkoutState" not in state:
            continue
        identity = dependency["packageRef"]["identity"]
        revision = pins[identity]
        checkout = packages / "checkouts" / dependency["subpath"]
        if checkout.parent != packages / "checkouts" or not (checkout / ".git").is_dir():
            return False
        actual = subprocess.run(["git", "-C", str(checkout), "rev-parse", "HEAD"],
                                check=True, capture_output=True, text=True).stdout.strip()
        if actual != revision or state["checkoutState"]["revision"] != revision:
            return False
        checked.add(checkout.name)
    # Fail closed for checkouts missing from the recorded dependency graph.
    return checked == {path.name for path in (packages / "checkouts").iterdir()}


if __name__ == "__main__":
    if sys.argv[1] == "--validate":
        try:
            valid = validate_revisions(Path(sys.argv[2]), Path(sys.argv[3]))
        except (OSError, ValueError, KeyError, TypeError, subprocess.CalledProcessError):
            valid = False
        if not valid:
            print("package snapshot skipped: checkout revisions do not match resolved pins", file=sys.stderr)
        sys.exit(0 if valid else 1)
    directory, old_repo, old_packages, new_repo, new_packages = sys.argv[1:]
    relocate_packages(Path(directory), old_repo, old_packages, new_repo, new_packages)
