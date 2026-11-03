"""Exercise build recovery without downloading or building dependencies."""

import hashlib
import http.server
import json
from pathlib import Path
import shlex
import socket
import subprocess
import sys
import tempfile
import threading
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


class ScriptRuntimeDownloadTests(unittest.TestCase):
    def download(self, responses):
        payload = b"pinned V8 archive fixture"
        requests = []

        class Handler(http.server.BaseHTTPRequestHandler):
            def do_GET(self):
                requests.append(self.path)
                response = responses[min(len(requests) - 1, len(responses) - 1)]
                if response == "disconnect":
                    self.connection.shutdown(socket.SHUT_RDWR)
                    self.connection.close()
                    return
                self.send_response(200 if response != "unavailable" else 503)
                self.end_headers()
                self.wfile.write(payload if response == "valid" else b"invalid archive")

            def log_message(self, *args):
                pass

        with tempfile.TemporaryDirectory(prefix="script-runtime-download-test-") as directory:
            with http.server.HTTPServer(("127.0.0.1", 0), Handler) as server:
                thread = threading.Thread(target=server.serve_forever, daemon=True)
                thread.start()
                source = (ROOT / "scripts/build-script-runtime.sh").read_text()
                build = source.split('    archive="$cache/v8/', 1)[1].split(
                    '\n    export RUSTY_V8_ARCHIVE=', 1
                )[0]
                build = '    archive="$cache/v8/' + build
                url = "https://github.com/denoland/rusty_v8/releases/download/v$V8_VERSION/librusty_v8_ptrcomp_release_aarch64-apple-darwin.a.gz"
                build = build.replace(url, f"http://127.0.0.1:{server.server_port}/archive")
                checks = source.split("has_sha256() {", 1)[1].split("\n}\n", 1)[0]
                setup = f'''set -euo pipefail
cache={shlex.quote(directory)}
V8_VERSION=fixture
V8_ARCHIVE_SHA256={hashlib.sha256(payload).hexdigest()}
give_up() {{ echo "$*" >&2; exit 1; }}
has_sha256() {{{checks}
}}
'''
                try:
                    result = subprocess.run(
                        ["bash", "-c", setup + build], text=True, capture_output=True, timeout=30
                    )
                finally:
                    server.shutdown()
                    thread.join()
                files = list(Path(directory).rglob("*.gz"))
                partials = list(Path(directory).rglob("*.partial"))
                return result, requests, files, partials

    def test_transient_connection_failure_recovers(self):
        result, requests, files, partials = self.download(["disconnect", "valid"])
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(len(requests), 2)
        self.assertEqual(len(files), 1)
        self.assertEqual(partials, [])

    def test_persistent_failure_stops_and_removes_partial(self):
        result, requests, files, partials = self.download(["unavailable"])
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(len(requests), 4)
        self.assertIn("couldn't download V8", result.stderr)
        self.assertEqual(files, [])
        self.assertEqual(partials, [])

    def test_checksum_mismatch_is_not_published_or_retried(self):
        result, requests, files, partials = self.download(["invalid"])
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(len(requests), 1)
        self.assertIn("pinned SHA-256", result.stderr)
        self.assertEqual(files, [])
        self.assertEqual(partials, [])


if __name__ == "__main__":
    unittest.main()
