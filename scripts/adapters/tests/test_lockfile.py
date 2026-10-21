import base64
from contextlib import redirect_stdout
import copy
import importlib.util
import io
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

SCRIPT = Path(__file__).resolve().parents[1] / "lockfile.py"
spec = importlib.util.spec_from_file_location("lockfile", SCRIPT)
tool = importlib.util.module_from_spec(spec)
spec.loader.exec_module(tool)
PACKAGE, VERSION = "@example/adapter", "1.2.3-beta.1+build.9"
PIN = {PACKAGE: VERSION}
RECORD = {"version": VERSION, "resolved": "https://registry.example/adapter.tgz",
          "integrity": "sha512-" + base64.b64encode(bytes(64)).decode(),
          "dependencies": {"child": "^2.0.0"}, "futureField": {"preserve": True}}
LOCK = {"lockfileVersion": 3, "packages": {"": {"dependencies": PIN},
        "node_modules/" + PACKAGE: RECORD, "node_modules/child": dict(RECORD, version="2.1.0", dependencies={})}}


class LockfileTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.output = self.root / "output"
        self.fixture = self.root / "fixture.json"
        self.fixture.write_text(json.dumps(LOCK))
        npm = self.root / "npm"
        npm.write_text(f"#!{sys.executable}\n" + """import json, os, pathlib, sys
p = pathlib.Path.cwd()
pathlib.Path(os.environ['TRACE']).write_text(json.dumps([sys.argv[1:], str(p), json.loads((p/'package.json').read_text())]))
(p/'package-lock.json').write_text(pathlib.Path(os.environ['FIXTURE']).read_text())
print('secret-token', file=sys.stderr)
sys.exit(int(os.environ.get('FAIL', '0')))
""")
        npm.chmod(0o755)
        self.env = dict(os.environ, PATH=str(self.root) + os.pathsep + os.environ.get("PATH", ""),
                        FIXTURE=str(self.fixture), TRACE=str(self.root / "trace"), npm_config_ignore_scripts="false")

    def cli(self, mode, *extra, env=None):
        return subprocess.run([sys.executable, str(SCRIPT), mode, PACKAGE, VERSION, str(self.output), *extra],
                              env=env or self.env, capture_output=True, text=True)

    def test_generate_and_check(self):
        for registry in (None, "https://mirror.example/npm/"):
            with self.subTest(registry=registry):
                self.output = self.root / ("default" if registry is None else "mirror")
                result = self.cli("generate", *([] if registry is None else ["--registry", registry]))
                self.assertEqual(result.returncode, 0, result.stderr)
                argv, cwd, manifest = json.loads((self.root / "trace").read_text())
                registry = registry or "https://registry.npmjs.org/"
                self.assertEqual(argv, ["install", "--package-lock-only", "--ignore-scripts", "--no-audit", "--no-fund",
                                       "--lockfile-version=3", "--global=false", "--prefix", cwd, "--cache", cwd + "/.npm",
                                       "--registry", registry, "--@example:registry=" + registry])
                self.assertEqual(Path(cwd).parent, self.output.resolve())
                self.assertEqual(manifest, {"name": "native-adapter-lock", "private": True, "dependencies": PIN})
                self.assertEqual((self.output / "package-lock.json").read_bytes(), self.fixture.read_bytes())
                self.assertFalse(Path(cwd).exists())
                with patch.object(tool.subprocess, "run", side_effect=AssertionError("subprocess")), \
                        patch("socket.socket", side_effect=AssertionError("network")), \
                        patch.object(sys, "argv", [str(SCRIPT), "check", PACKAGE, VERSION, str(self.output)]), \
                        redirect_stdout(io.StringIO()):
                    tool.main()
                self.assertEqual(self.cli("check", env=dict(self.env, PATH="")).returncode, 0)

    def test_failed_generation_and_existing_output(self):
        for failure in ("npm", "audit", "existing"):
            with self.subTest(failure=failure):
                self.output = self.root / failure
                self.fixture.write_text(json.dumps(LOCK) if failure != "audit" else "{}")
                if failure == "existing":
                    self.output.mkdir()
                    (self.output / "keep").write_text("untouched")
                    (self.root / "trace").unlink()
                result = self.cli("generate", env=dict(self.env, FAIL="7" if failure == "npm" else "0"))
                self.assertNotEqual(result.returncode, 0)
                self.assertNotIn("secret-token", result.stdout + result.stderr)
                self.assertFalse((self.output / "package-lock.json").exists())
                self.assertNotEqual(self.cli("check").returncode, 0)
                if failure == "existing":
                    self.assertEqual((self.output / "keep").read_text(), "untouched")
                    self.assertFalse((self.root / "trace").exists())

    def test_audit_rejections(self):
        self.output.mkdir()
        manifest = self.output / "package.json"
        manifest.write_text(json.dumps({"dependencies": PIN}))
        cases = [("lock", "lockfileVersion", x) for x in (None, 2, "3", 3.0)]
        cases += [("lock", "packages", x) for x in (None, [], {})]
        cases += [("root", "dependencies", x) for x in ({}, {PACKAGE: "^1.2.3"}, {"wrong": VERSION})]
        cases += [("root", "devDependencies", {"extra": "1.0.0"}), ("root", "link", True)]
        cases += [("record", "version", x) for x in (None, "latest", "^1.2.3", "file:../x", "git+https://example/x", "01.2.3", "1.2.3-01")]
        cases += [("record", "resolved", x) for x in (None, "http://example/a.tgz", "file:../x", "git+https://example/x", "https:///a", "https://example", "https://user:token@example/a", "https://example:bad/a")]
        cases += [("record", "integrity", x) for x in (None, "sha1-abc", "sha512-!", "sha512-YQ==", RECORD["integrity"][:-3] + "B==")]
        cases += [("record", "link", True), ("packages", "node_modules/child", []),
                  ("packages", "", []),
                  ("packages", "node_modules/" + PACKAGE, {}), ("packages", "workspace", RECORD)]
        for target, key, value in cases:
            with self.subTest(target=target, key=key, value=value):
                lock = copy.deepcopy(LOCK)
                {"lock": lock, "packages": lock["packages"], "root": lock["packages"][""],
                 "record": lock["packages"]["node_modules/child"]}[target][key] = value
                (self.output / "package-lock.json").write_text(json.dumps(lock))
                with self.assertRaises(ValueError):
                    tool.audit(self.output, PACKAGE, VERSION)
        for text in ("{", "[]", "null"):
            (self.output / "package-lock.json").write_text(text)
            self.assertNotEqual(self.cli("check").returncode, 0)
        (self.output / "package-lock.json").write_text(json.dumps(LOCK))
        manifest.write_text(json.dumps({"dependencies": {PACKAGE: "1.0.0"}}))
        self.assertNotEqual(self.cli("check").returncode, 0)

    def test_invalid_inputs(self):
        for package, version, registry in (("../x", VERSION, "https://example/"),
                                           (PACKAGE, "latest", "https://example/"),
                                           (PACKAGE, VERSION, "http://example/")):
            with self.assertRaises(ValueError):
                tool.generate(self.output, package, version, registry)
            self.assertFalse(self.output.exists())
