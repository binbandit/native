import base64
import hashlib
import importlib.util
import json
from pathlib import Path
import re
import tempfile
import unittest
from unittest.mock import patch

_spec = importlib.util.spec_from_file_location("offline_bundle", Path(__file__).parents[1] / "offline-bundle.py")
bundle = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(bundle)
REPOSITORY = Path(__file__).resolve().parents[3]
PI_PAIR = REPOSITORY / "adapters/pi"


class BuiltInPiPairTests(unittest.TestCase):
    """The reviewed Pi pair stays audited and matches the pin PiPlugin launches."""

    def test_audits_offline(self):
        with patch("subprocess.run", side_effect=AssertionError("process")), \
                patch("socket.socket", side_effect=AssertionError("network")):
            bundle.lockfile.audit(PI_PAIR, "pi-acp", "0.0.34")

    def test_matches_plugin_pin(self):
        plugin = (REPOSITORY / "native/Plugins/PiPlugin.swift").read_text(encoding="utf-8")
        pinned = re.findall(r'"pi-acp@([^"]+)"', plugin)
        package = json.loads((PI_PAIR / "package.json").read_text(encoding="utf-8"))
        self.assertEqual(pinned, [package["dependencies"]["pi-acp"]])

    def test_missing_archives_publish_nothing(self):
        with tempfile.TemporaryDirectory(prefix="offline-bundle-pi-") as temporary:
            root = Path(temporary).resolve()
            (root / "archives").mkdir()
            with self.assertRaises(FileNotFoundError):
                bundle.build(PI_PAIR, root / "archives", root / "output", adapter="pi-acp", version="0.0.34",
                             os_name="darwin", architecture="arm64", node_version="26.12.1",
                             npm_version="11.20.0", agent_version="1.3.0",
                             entry="node_modules/pi-acp/dist/index.js")
            self.assertFalse((root / "output").exists())


class OfflineBundleTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix="offline-bundle-test-")
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name).resolve()
        self.pair, self.archives = self.root / "pair", self.root / "archives"
        self.pair.mkdir()
        self.archives.mkdir()
        self.archive = b"synthetic, not executed"
        self.digest = hashlib.sha512(self.archive).hexdigest()
        (self.archives / (self.digest + ".tgz")).write_bytes(self.archive)
        root = {"dependencies": {"fixture": "1.0.0"}}
        (self.pair / "package.json").write_text(json.dumps(root))
        self.lock = {"lockfileVersion": 3, "packages": {"": root, "node_modules/fixture": {
            "version": "1.0.0", "resolved": "https://fixture.invalid/fixture.tgz",
            "integrity": "sha512-" + base64.b64encode(hashlib.sha512(self.archive).digest()).decode(),
        }}}
        (self.pair / "package-lock.json").write_text(json.dumps(self.lock))

    def build(self, name="output"):
        return bundle.build(self.pair, self.archives, self.root / name, adapter="fixture", version="1.0.0",
                            os_name="darwin", architecture="arm64", node_version="26.12.1", npm_version="11.20.0",
                            agent_version="1.0.0", entry="node_modules/fixture/main.js")

    def test_deterministic_without_process_or_network(self):
        with patch("subprocess.run", side_effect=AssertionError("process")), patch("socket.socket", side_effect=AssertionError("network")):
            first, second = self.build(), self.build("second")
        self.assertEqual(first, second)
        manifest = json.loads((self.root / "output/bundle.json").read_bytes())
        self.assertIn("node_modules/fixture/package.json", manifest["requiredInstalledFiles"])
        for payload in manifest["payloads"]:
            data = (self.root / "output" / payload["path"]).read_bytes()
            self.assertEqual(payload["size"], len(data))
            self.assertEqual(payload["sha256"], hashlib.sha256(data).hexdigest())

    def test_missing_corrupt_link_and_permissions(self):
        path = self.archives / (self.digest + ".tgz")
        for mode in ("missing", "corrupt", "link", "permissions"):
            with self.subTest(mode=mode):
                path.unlink(missing_ok=True)
                if mode == "link":
                    path.symlink_to(self.pair / "package.json")
                elif mode != "missing":
                    path.write_bytes(b"bad" if mode == "corrupt" else self.archive)
                    path.chmod(0o666 if mode == "permissions" else 0o600)
                with self.assertRaises((OSError, ValueError)):
                    self.build()
                self.assertFalse((self.root / "output").exists())

    def test_existing_output_is_preserved(self):
        (self.root / "output").mkdir()
        with self.assertRaises(FileExistsError):
            self.build()
        self.assertEqual(list((self.root / "output").iterdir()), [])


if __name__ == "__main__":
    unittest.main()
