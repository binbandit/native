import configparser
import importlib.util
import os
from pathlib import Path
import re
import shlex
import shutil
import subprocess
import sys
import tempfile
import unittest


SCRIPT = Path(__file__).resolve().parents[1] / "render-systemd-unit.py"
SPEC = importlib.util.spec_from_file_location("systemd_unit", SCRIPT)
renderer = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(renderer)


class SystemdUnitTests(unittest.TestCase):
    def test_exact_fields_and_restart_on_exit_75(self):
        unit = configparser.ConfigParser(interpolation=None)
        unit.optionxform = str
        unit.read_string(renderer.render("/opt/native-host", "/tmp/native-state"))
        self.assertEqual(unit.sections(), ["Unit", "Service", "Install"])
        self.assertEqual(dict(unit["Unit"]), {"Description": "Native host"})
        self.assertEqual(dict(unit["Service"]), {
            "Type": "simple",
            "ExecStart": ':"/opt/native-host" serve --home "/tmp/native-state"',
            "Restart": "on-failure", "RestartSec": "3s",
            "UMask": "0077", "KillMode": "control-group",
        })
        self.assertEqual(dict(unit["Install"]), {"WantedBy": "default.target"})
        # Nonzero 75 is a failure under systemd's defaults; 0 stays stopped.
        for override in ("SuccessExitStatus", "RestartPreventExitStatus", "RestartForceExitStatus"):
            self.assertNotIn(override, unit["Service"])

    def test_literal_arguments(self):
        executable = "/opt/native host %n $HOME"
        state = '/tmp/a "quote" \\ %n ${HOME} $USER $$ ; # \'single\' 雪/'
        line = renderer.render(executable, state).splitlines()[5]
        self.assertEqual(line, 'ExecStart=:\"/opt/native host %%n $HOME\" serve --home '
                         '\"/tmp/a \\\"quote\\\" \\\\ %%n ${HOME} $USER $$ ; # \'single\' 雪/\"')

    def test_invalid_paths(self):
        for bad in ("", "relative", "~/host", "C:\\host", "/", "//", "/tmp/..",
                    "/tmp/\0host", "/tmp/\nhost", "/tmp/\rhost", "/tmp/\thost", "/tmp/\x7fhost"):
            for arguments in ((bad, "/tmp/state"), ("/bin/true", bad)):
                with self.subTest(arguments=arguments), self.assertRaises(ValueError):
                    renderer.render(*arguments)
        for bad in ('/tmp/a"b', "/tmp/a'b", "/tmp/a\\b", "/tmp/host/"):
            with self.subTest(executable=bad), self.assertRaises(ValueError):
                renderer.render(bad, "/tmp/state")

    def test_cli_stdout_and_errors(self):
        arguments = [sys.executable, str(SCRIPT), "--executable", "/bin/true", "--state-directory"]
        result = subprocess.run(arguments + ["/tmp/native state"], capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout, renderer.render("/bin/true", "/tmp/native state"))
        self.assertEqual(result.stderr, "")
        for tail in ([], ["relative"], ["/tmp/\n[Service]\nExecStart=/bin/false"]):
            result = subprocess.run(arguments + tail, capture_output=True, text=True)
            self.assertEqual(result.returncode, 2)
            self.assertEqual(result.stdout, "")

    @unittest.skipUnless(sys.platform.startswith("linux"), "real systemd parser requires Linux CI")
    def test_linux_parser_and_decoded_arguments(self):
        analyzer = shutil.which("systemd-analyze")
        self.assertIsNotNone(analyzer, "Linux validation pending: systemd-analyze is required")
        harmless = shutil.which("true")
        self.assertIsNotNone(harmless)
        with tempfile.TemporaryDirectory(prefix="native-systemd-") as scratch:
            root = Path(scratch)
            executable = root / "host %n $HOME"
            executable.symlink_to(harmless)
            state = root / 'state "quote" \\ %n ${HOME} $USER $$ ; # \'single\' 雪'
            unit = root / "native-host.service"
            unit.write_text(renderer.render(str(executable), str(state)), encoding="utf-8")
            # A standalone parser with scratch units, never a connection to a user manager.
            for target in ("basic", "shutdown", "default"):
                (root / f"{target}.target").write_text("[Unit]\nDescription=Scratch target\n")
            environment = dict(os.environ, XDG_RUNTIME_DIR=scratch, SYSTEMD_UNIT_PATH=scratch,
                               SYSTEMD_LOG_LEVEL="debug", SYSTEMD_LOG_COLOR="0")
            result = subprocess.run([analyzer, "--user", "verify", "--man=no", str(unit)],
                                    env=environment, capture_output=True, text=True, timeout=30)
            output = result.stdout + result.stderr
            self.assertEqual(result.returncode, 0, output)
            commands = re.findall(r"Command Line: (.+)", output)
            self.assertEqual(len(commands), 1, output)
            self.assertEqual(shlex.split(commands[0]), [str(executable), "serve", "--home", str(state)])
            self.assertFalse(state.exists(), "verification must not execute the unit")
            print("Linux parser accepted native-host.service and preserved its literal arguments")


if __name__ == "__main__":
    unittest.main()
