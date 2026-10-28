"""Check launcher defaults without opening an app or touching its defaults."""
import pathlib
import subprocess
import unittest
import tempfile

ROOT = pathlib.Path(__file__).resolve().parents[2]


class SilentLaunchTests(unittest.TestCase):
    def arguments(self, *overrides):
        source = (ROOT / "scripts/dev/run-isolated.sh").read_text()
        start = source.index("defaults_args=()")
        end = source.index("# In the background", start)
        result = subprocess.run(
            ["bash", "-c", 'app_args=("$@"); worktrees=/tmp/fixture\n'
             + source[start:end] + '\nprintf "%s\\n" "${defaults_args[@]}"', "test", *overrides],
            check=True, text=True, capture_output=True,
        )
        return result.stdout.splitlines()

    def test_silent_by_default(self):
        args = self.arguments()
        self.assertIn("-sounds.enabled", args)
        self.assertEqual(args[args.index("-sounds.enabled") + 1], "NO")
        self.assertIn("-native.mute", args)
        self.assertEqual(args[args.index("-native.mute") + 1], "YES")

    def test_explicit_overrides(self):
        args = self.arguments("-sounds.enabled", "YES", "-native.mute", "NO")
        self.assertNotIn("-sounds.enabled", args)
        self.assertNotIn("-native.mute", args)


class AudioPolicyTests(unittest.TestCase):
    def test_debug_and_shipping_defaults_and_overrides(self):
        with tempfile.TemporaryDirectory(prefix="native-audio-policy-") as directory:
            main = pathlib.Path(directory) / "main.swift"
            main.write_text('print(NativeAudioPolicy.isMuted ? "muted" : "audible")')
            for debug in (True, False):
                binary = str(pathlib.Path(directory) / ("debug" if debug else "shipping"))
                subprocess.run(
                    ["nice", "-n", "10", "swiftc", "-swift-version", "6"]
                    + (["-D", "DEBUG"] if debug else [])
                    + [str(ROOT / "native/Sounds/Playback/NativeAudioPolicy.swift"), str(main), "-o", binary],
                    check=True, capture_output=True, text=True,
                )
                for args, expected in (([], "muted" if debug else "audible"),
                                       (["-native.mute", "YES"], "muted"),
                                       (["-native.mute", "NO"], "audible")):
                    result = subprocess.run([binary, *args], check=True, capture_output=True, text=True)
                    self.assertEqual(result.stdout.strip(), expected)


if __name__ == "__main__":
    unittest.main()
