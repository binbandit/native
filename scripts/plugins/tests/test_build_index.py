import hashlib
import json
from pathlib import Path
import subprocess
import sys
import tarfile
import tempfile
import unittest


SCRIPT = Path(__file__).resolve().parents[1] / "build-index.py"
REPOSITORY = "https://example.org/owner/plugins"
BASE = "https://example.org/assets"


class BuildIndexTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.repo = self.root / "repo"
        self.repo.mkdir()
        self.git("init", "--quiet")
        for plugin_id in ("example", "zeta"):
            self.write(f"plugins/{plugin_id}/plugin.json", json.dumps(
                dict(id=plugin_id, name=plugin_id.title(), version="1.0.0", future=True)))
        self.write("plugins/example/assets/run", "committed\n").chmod(0o755)
        self.write("plugins/example/assets/" + "a" * 110 + "é", "long UTF-8 path")
        self.commit = self.commit_tree()

    def git(self, *args):
        return subprocess.check_output(["git", "-C", str(self.repo), "-c", "user.name=Test",
                                        "-c", "user.email=test@example.org", "-c", "commit.gpgsign=false",
                                        "-c", "core.precomposeUnicode=false",
                                        "-c", "core.hooksPath=/dev/null", *args], stderr=subprocess.PIPE).decode().strip()

    def write(self, path, text):
        target = self.repo / path
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_text(text, encoding="utf-8")
        return target

    def commit_tree(self):
        self.git("add", ".")
        self.git("commit", "--quiet", "-m", "fixture")
        return self.git("rev-parse", "HEAD")

    def run_builder(self, name="output", commit=None, extra=(), success=True):
        output = self.root / name
        result = subprocess.run([sys.executable, str(SCRIPT), "--repository", str(self.repo),
                                 "--commit", commit or self.commit, "--repository-url", REPOSITORY,
                                 "--asset-base-url", BASE + "/", "--output", str(output), *extra],
                                capture_output=True, text=True)
        self.assertEqual(result.returncode == 0, success, result.stderr)
        if not success:
            self.assertFalse((output / "index.json").exists())
        return output

    def test_reproducible_committed_bytes_and_metadata(self):
        first = self.run_builder("first")
        self.write("plugins/example/plugin.json", "uncommitted invalid JSON")
        self.write("plugins/example/untracked", "ignored")
        second = self.run_builder("second")
        self.assertEqual({p.relative_to(first): p.read_bytes() for p in first.rglob("*") if p.is_file()},
                         {p.relative_to(second): p.read_bytes() for p in second.rglob("*") if p.is_file()})
        index = json.loads((first / "index.json").read_bytes())
        self.assertEqual(index["schema"], 1)
        self.assertEqual([p["id"] for p in index["plugins"]], ["example", "zeta"])
        for entry in index["plugins"]:
            data = (first / self.commit / (entry["id"] + ".tar")).read_bytes()
            self.assertEqual(entry, dict(id=entry["id"], version="1.0.0", repository=REPOSITORY,
                                        commit=self.commit, path="plugins/" + entry["id"],
                                        archiveURL=f"{BASE}/{self.commit}/{entry['id']}.tar",
                                        sha256=hashlib.sha256(data).hexdigest(), size=len(data)))
        with tarfile.open(first / self.commit / "example.tar") as tar:
            self.assertEqual(tar.getnames(), sorted(tar.getnames()))
            for member in tar:
                self.assertTrue(member.isfile())
                self.assertEqual((member.mtime, member.uid, member.gid, member.uname, member.gname),
                                 (0, 0, 0, "", ""))
            self.assertEqual(tar.getmember("assets/run").mode, 0o755)
            self.assertEqual(tar.getmember("plugin.json").mode, 0o644)
            self.assertEqual(tar.extractfile("plugin.json").read().decode(),
                             self.git("show", f"{self.commit}:plugins/example/plugin.json"))

    def test_changed_commit_changes_only_affected_archive(self):
        first = self.run_builder("first")
        self.write("plugins/example/assets/run", "changed")
        second = self.run_builder("second", self.commit_tree())
        digests = lambda folder: [p["sha256"] for p in json.loads((folder / "index.json").read_bytes())["plugins"]]
        self.assertNotEqual(digests(first)[0], digests(second)[0])
        self.assertEqual(digests(first)[1], digests(second)[1])

    def test_invalid_manifests_leave_no_index(self):
        for invalid in ("{", "[]", '{"id":"example","name":"X","version":"1"}',
                        '{"id":"other","name":"X","version":"1"}',
                        '{"id":"zeta","id":"zeta","name":"X","version":"1"}',
                        '{"id":"zeta","name":"X"}',
                        '{"id":"zeta","name":"","version":"1"}',
                        '{"id":"zeta","name":"X","version":2}'):
            with self.subTest(invalid=invalid):
                self.write("plugins/zeta/plugin.json", invalid)
                self.run_builder(commit=self.commit_tree(), success=False)
        (self.repo / "plugins/zeta/plugin.json").unlink()
        self.write("plugins/zeta/asset", "missing manifest")
        self.run_builder(commit=self.commit_tree(), success=False)

    def test_rejected_inputs(self):
        for number, extra in enumerate((("--commit", "0" * 40), ("--commit", "HEAD"),
                      ("--repository-url", "http://example.org"),
                      ("--asset-base-url", BASE + "?"), ("--asset-base-url", BASE + "#"),
                      ("--asset-base-url", "https://user@example.org/assets"))):
            with self.subTest(extra=extra):
                self.run_builder(name=f"input-{number}", extra=extra, success=False)
        for mode, oid, path in (("120000", self.git("rev-parse", "HEAD:plugins/example/plugin.json"), "link"),
                                ("160000", self.commit, "submodule"),
                                ("100644", self.git("rev-parse", "HEAD:plugins/example/plugin.json"), "bad\\path")):
            with self.subTest(path=path):
                self.git("update-index", "--add", "--cacheinfo", f"{mode},{oid},plugins/example/{path}")
                self.git("commit", "--quiet", "-m", "invalid entry")
                self.run_builder(commit=self.git("rev-parse", "HEAD"), success=False)
                self.git("reset", "--hard", self.commit)
        existing = self.root / "output"
        existing.mkdir()
        sentinel = existing / "keep"
        sentinel.write_bytes(b"untouched")
        self.run_builder(success=False)
        self.assertEqual(sentinel.read_bytes(), b"untouched")

    def test_aliased_paths_leave_no_index(self):
        oid = self.git("rev-parse", "HEAD:plugins/example/plugin.json")
        for number, paths in enumerate((("assets/Icon.png", "assets/icon.png"),
                                        ("Assets", "assets/nested"), ("assets/é", "assets/e\u0301"))):
            with self.subTest(paths=paths):
                self.git("reset", "--hard", self.commit)
                for path in paths:
                    self.git("update-index", "--add", "--cacheinfo", f"100644,{oid},plugins/example/{path}")
                self.git("commit", "--quiet", "-m", "aliased paths")
                self.run_builder(name=f"alias-{number}", commit=self.git("rev-parse", "HEAD"), success=False)
