import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest


class InstallUserServiceTests(unittest.TestCase):
    def setUp(self):
        scratch = tempfile.TemporaryDirectory(prefix="native-install-")
        self.addCleanup(scratch.cleanup)
        self.root = Path(scratch.name).resolve()
        self.config = self.root / "config space %n"
        self.state = self.root / "state space %n"
        self.host = self.root / "host space %n"
        self.target = self.config / "systemd/user/native-host.service"
        self.calls = self.root / "calls.jsonl"
        self.host.write_text("#!" + sys.executable + "\nraise SystemExit(77)\n")
        self.host.chmod(0o700)
        fake = self.root / "systemctl"
        fake.write_text("#!" + sys.executable + "\nimport json, os, sys\n"
                        "with open(os.environ['CALLS'], 'a') as log:\n"
                        "    log.write(json.dumps(sys.argv[1:]) + '\\n')\n"
                        "if 'show' in sys.argv: print(os.environ['FRAGMENT'])\n"
                        "sys.exit(9 if os.environ.get('FAIL') in sys.argv[1:] else 0)\n")
        fake.chmod(0o700)
        for name in ("install-user-service.py", "render-systemd-unit.py"):
            shutil.copyfile(Path(__file__).resolve().parents[1] / name, self.root / name)
        self.env = {"PATH": str(self.root), "HOME": str(self.root), "CALLS": str(self.calls),
                    "XDG_CONFIG_HOME": str(self.config), "XDG_RUNTIME_DIR": str(self.root / "runtime"),
                    "FRAGMENT": str(self.target)}
        self.args = ["--executable", str(self.host), "--state-directory", str(self.state)]
        # Apple Python caches interpreter startup in HOME before running any script.
        subprocess.run([sys.executable, "-c", "pass"], env=self.env, check=True)

    def run_cli(self, *extra, args=None):
        return subprocess.run([sys.executable, str(self.root / "install-user-service.py")]
                              + (self.args if args is None else args) + list(extra),
                              env=self.env, capture_output=True, text=True, timeout=10)

    def commands(self):
        return [json.loads(line) for line in self.calls.read_text().splitlines()] if self.calls.exists() else []

    def snapshot(self):
        return {str(path): (path.lstat().st_mode, path.lstat().st_mtime_ns,
                           path.read_bytes() if path.is_file() else None)
                for path in [self.root, *self.root.rglob("*")]}

    def test_dry_run_has_zero_side_effects(self):
        before = self.snapshot()
        result = self.run_cli("--dry-run", "--enable-now")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(json.loads(result.stdout), {"target": str(self.target), "argv": [
            ["systemctl", "--user", "daemon-reload"],
            ["systemctl", "--user", "show", "--property=FragmentPath", "--value", "native-host.service"],
            ["systemctl", "--user", "enable", "--now", "native-host.service"]]})
        self.assertEqual(self.snapshot(), before)

    def test_install_exact_bytes_and_identical_retry(self):
        expected = subprocess.run([sys.executable, str(self.root / "render-systemd-unit.py")] + self.args,
                                  env=self.env, capture_output=True, check=True).stdout
        result = self.run_cli()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.target.read_bytes(), expected)
        self.assertEqual(self.target.stat().st_mode & 0o777, 0o600)
        self.assertEqual(self.commands(), [["--user", "daemon-reload"]])
        original = self.target.stat()
        result = self.run_cli("--enable-now")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.target.stat().st_ino, original.st_ino)
        self.assertEqual(self.target.stat().st_mtime_ns, original.st_mtime_ns)
        self.assertEqual(self.commands()[1:], [["--user", "daemon-reload"],
                                              ["--user", "show", "--property=FragmentPath", "--value", "native-host.service"],
                                              ["--user", "enable", "--now", "native-host.service"]])
        self.assertEqual(list(self.target.parent.iterdir()), [self.target])
        self.assertFalse(self.state.exists())

    def test_config_defaults_and_override(self):
        for xdg in ("", "relative", str(self.config)):
            self.env["XDG_CONFIG_HOME"] = xdg
            result = self.run_cli("--dry-run")
            base = self.config if xdg.startswith("/") else self.root / ".config"
            self.assertEqual(json.loads(result.stdout)["target"], str(base / "systemd/user/native-host.service"))
        result = self.run_cli("--dry-run", "--config-home", str(self.root / "override"))
        self.assertEqual(json.loads(result.stdout)["target"], str(self.root / "override/systemd/user/native-host.service"))

    def test_refuse_different_nonregular_and_symlink_units(self):
        self.target.parent.mkdir(parents=True)
        identical = self.root / "identical.service"
        self.assertEqual(self.run_cli().returncode, 0)
        self.target.rename(identical)
        self.calls.unlink()
        for kind in ("different", "directory", "fifo", "symlink", "dangling"):
            with self.subTest(kind=kind):
                if kind == "different":
                    self.target.write_bytes(b"unrelated service\n")
                elif kind == "directory":
                    self.target.mkdir()
                elif kind == "fifo":
                    os.mkfifo(self.target)
                else:
                    self.target.symlink_to(identical if kind == "symlink" else self.root / "missing")
                for extra in ([], ["--dry-run"]):
                    before = self.snapshot()
                    self.assertEqual(self.run_cli(*extra).returncode, 1)
                    self.assertEqual(self.snapshot(), before)
                self.target.rmdir() if kind == "directory" else self.target.unlink()
        self.assertEqual(self.commands(), [])

    def test_refuse_symlink_destination_parents(self):
        for path in (self.config, self.config / "systemd", self.target.parent):
            with self.subTest(path=path):
                path.parent.mkdir(parents=True, exist_ok=True)
                path.symlink_to(self.root, target_is_directory=True)
                before = self.snapshot()
                self.assertEqual(self.run_cli().returncode, 1)
                self.assertEqual(self.run_cli("--dry-run").returncode, 1)
                self.assertEqual(self.snapshot(), before)
                path.unlink()

    def test_invalid_inputs_create_nothing(self):
        for option, value in [(option, bad) for option in ("--executable", "--state-directory", "--config-home")
                              for bad in ("", "relative", "/", "/tmp/\nunit")] + [
                                  ("--executable", str(self.root / "missing")),
                                  ("--executable", str(self.root)),
                                  ("--state-directory", str(self.host)),
                                  ("--config-home", str(self.root / ".." / "outside"))]:
            with self.subTest(option=option, value=value):
                before = self.snapshot()
                self.assertEqual(self.run_cli(option, value).returncode, 1)
                self.assertEqual(self.snapshot(), before)
        self.host.chmod(0o600)
        self.assertEqual(self.run_cli().returncode, 1)
        self.assertEqual(self.run_cli(args=[]).returncode, 2)
        self.assertFalse(self.config.exists())
        self.assertEqual(self.commands(), [])

    def test_failed_reload_and_enable_retain_unit_for_retry(self):
        for failure, completed, count in (("daemon-reload", "daemon-reload not completed", 1),
                                           ("show", "daemon-reload completed", 2),
                                           ("enable", "daemon-reload completed", 3)):
            with self.subTest(failure=failure):
                self.env["FAIL"] = failure
                result = self.run_cli("--enable-now")
                self.assertEqual(result.returncode, 1)
                self.assertIn(completed, result.stderr)
                self.assertIn("rerun the same command", result.stderr)
                self.assertEqual(len(self.commands()), count)
                self.assertTrue(self.target.is_file())
                self.calls.unlink()
        del self.env["FAIL"]
        self.assertEqual(self.run_cli("--enable-now").returncode, 0)

    def test_refuse_activation_of_shadowing_or_missing_fragment(self):
        shadow = self.config / "systemd/user.control/native-host.service"
        shadow.parent.mkdir(parents=True)
        shadow.write_bytes(b"unrelated service\n")
        for fragment in (str(shadow), "", str(self.root / "missing.service")):
            with self.subTest(fragment=fragment):
                self.env["FRAGMENT"] = fragment
                before = self.snapshot()
                self.assertEqual(self.run_cli("--dry-run", "--enable-now").returncode, 0)
                self.assertEqual(self.snapshot(), before)
                result = self.run_cli("--enable-now")
                self.assertEqual(result.returncode, 1)
                self.assertIn("daemon-reload completed", result.stderr)
                self.assertEqual([command[1] for command in self.commands()], ["daemon-reload", "show"])
                self.assertEqual(shadow.read_bytes(), b"unrelated service\n")
                self.assertTrue(self.target.is_file())
                self.calls.unlink()

    def test_missing_systemctl_retains_unit(self):
        (self.root / "systemctl").unlink()
        result = self.run_cli("--enable-now")
        self.assertEqual(result.returncode, 1)
        self.assertIn("daemon-reload not completed", result.stderr)
        self.assertTrue(self.target.is_file())
        self.assertEqual(self.commands(), [])


if __name__ == "__main__":
    unittest.main()
