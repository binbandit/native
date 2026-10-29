"""Package snapshots must survive removal of their original instance and remain independent."""
import importlib.util
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[3]
SPEC = importlib.util.spec_from_file_location("state", ROOT / "scripts/dev/build-cache-state.py")
STATE = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(STATE)


class BuildCacheTests(unittest.TestCase):
    def test_path_mapping_respects_boundaries_and_preserves_urls(self):
        value = {"path": "/old/Packages/A", "other": "/older/Packages/A",
                 "url": "https://host/old/source", "array": ["/old"]}
        self.assertEqual(STATE.relocate(value, [("/old", "/new")]), {
            "path": "/new/Packages/A", "other": "/older/Packages/A",
            "url": "https://host/old/source", "array": ["/new"]})

    def test_snapshot_relocation_and_copy_on_write(self):
        with tempfile.TemporaryDirectory(prefix="native-cache-test-") as directory:
            root = Path(directory)
            repo = root / "repo with spaces"
            (repo / "native.xcodeproj/project.xcworkspace/xcshareddata/swiftpm").mkdir(parents=True)
            resolved = repo / "native.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved"
            resolved.write_text('{"pins": []}')
            (repo / "native.xcodeproj/project.pbxproj").write_text("project")
            (repo / "Packages/A").mkdir(parents=True)
            (repo / "Packages/A/Package.swift").write_text("manifest")
            (repo / "scripts/dev").mkdir(parents=True)
            for name in ["build-cache.sh", "build-cache-state.py"]:
                shutil.copy2(ROOT / "scripts/dev" / name, repo / "scripts/dev" / name)
            before = root / "before"
            packages = before / "SourcePackages"
            bare = packages / "repositories/A"
            bare.parent.mkdir(parents=True)
            def git(*args):
                return subprocess.run(["git", *map(str, args)], check=True, capture_output=True, text=True)
            source = root / "source"
            git("init", source)
            (source / "value").write_text("original")
            git("-C", source, "add", "value")
            git("-C", source, "-c", "user.name=Fixture", "-c", "user.email=fixture@example.invalid",
                "commit", "-m", "fixture")
            git("clone", "--bare", source, bare)
            checkout = packages / "checkouts/A"
            checkout.parent.mkdir()
            git("clone", "--shared", bare, checkout)
            (packages / "artifacts").mkdir()
            (packages / "workspace-state.json").write_text(json.dumps({
                "object": {"path": str(repo / "Packages/A"), "artifact": str(packages / "artifacts/a")}}))
            env = dict(os.environ, NATIVE_DEV_CACHE=str(root / "cache"))
            script = repo / "scripts/dev/build-cache.sh"
            def run(action, derived):
                subprocess.run([str(script), action, str(repo), str(derived)], env=env, check=True,
                               capture_output=True, text=True)
            run("publish", before)
            snapshots = list((root / "cache/packages-v1").glob("[!.]*"))
            self.assertEqual(len(snapshots), 1)
            shutil.rmtree(before)
            moved_repo = root / "another worktree"
            repo.rename(moved_repo)
            repo = moved_repo
            resolved = repo / "native.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved"
            script = repo / "scripts/dev/build-cache.sh"
            after = root / "after"
            after.mkdir()
            run("prepare", after)
            seeded = after / "SourcePackages"
            git("-C", seeded / "checkouts/A", "fsck", "--full")
            self.assertEqual(git("-C", seeded / "checkouts/A", "show", "HEAD:value").stdout, "original")
            state = json.loads((seeded / "workspace-state.json").read_text())
            self.assertEqual(state['object']['artifact'], str(seeded / "artifacts/a"))
            self.assertEqual(state['object']['path'], str(repo / "Packages/A"))
            (seeded / "checkouts/A/value").write_text("changed")
            self.assertEqual((snapshots[0] / "checkouts/A/value").read_text(), "original")
            # Changed pins cannot seed the old graph, and dirty dependency sources cannot publish.
            resolved.write_text('{"pins": ["changed"]}')
            fresh = root / "fresh"
            fresh.mkdir()
            run("prepare", fresh)
            self.assertFalse((fresh / "SourcePackages").exists())
            run("publish", after)
            self.assertEqual(len(list((root / "cache/packages-v1").glob("[!.]*"))), 1)


if __name__ == "__main__":
    unittest.main()
