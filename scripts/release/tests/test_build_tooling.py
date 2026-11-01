"""Exercise compiler crash recovery without downloading or building dependencies."""

import json
from pathlib import Path
import shlex
import subprocess
import sys
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[3]


class LibghosttyBuildTests(unittest.TestCase):
    def build(self, statuses):
        with tempfile.TemporaryDirectory(prefix="libghostty-test-") as directory:
            root = Path(directory)
            state = root / "state.json"
            state.write_text(json.dumps({"statuses": statuses, "calls": []}))
            zig = root / "zig"
            zig.write_text(f'''#!{sys.executable}
import json
from pathlib import Path
import sys
state = Path({str(state)!r})
data = json.loads(state.read_text())
data["calls"].append(sys.argv[1:])
status = data["statuses"].pop(0)
state.write_text(json.dumps(data))
sys.exit(status)
''')
            zig.chmod(0o755)
            source = (ROOT / "scripts/build-libghostty.sh").read_text()
            build = source.split("started=$SECONDS\n", 1)[1].split("\nframework=", 1)[0]
            setup = f'''
set -euo pipefail
give_up() {{ echo "$*" >&2; exit 1; }}
src={shlex.quote(str(root))}
prefix="$src/out"
zig="$src/zig"
zig_env=(env)
zig_args=(-Doptimize=ReleaseFast)
'''
            result = subprocess.run(["bash", "-c", setup + build], text=True, capture_output=True)
            return result, json.loads(state.read_text())["calls"]

    def test_success_does_not_retry(self):
        result, calls = self.build([0])
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(len(calls), 1)

    def test_segfault_retries_once_with_single_job(self):
        result, calls = self.build([139, 0])
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(len(calls), 2)
        self.assertIn("-j1", calls[1])
        self.assertIn("segmentation fault", result.stdout)

    def test_compile_error_does_not_retry(self):
        result, calls = self.build([1])
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(len(calls), 1)
        self.assertIn("libghostty didn't build", result.stderr)

    def test_repeated_segfault_or_failed_retry_still_fails(self):
        for status in (1, 139):
            with self.subTest(status=status):
                result, calls = self.build([139, status])
                self.assertNotEqual(result.returncode, 0)
                self.assertEqual(len(calls), 2)
                self.assertIn("libghostty didn't build", result.stderr)


if __name__ == "__main__":
    unittest.main()
