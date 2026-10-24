"""Exercise release plans without builds, credentials, or publishing."""

from pathlib import Path
import importlib.util
import subprocess
import tempfile
import unittest
import xml.etree.ElementTree as ET


ROOT = Path(__file__).resolve().parents[3]
spec = importlib.util.spec_from_file_location("deltas", ROOT / "scripts/release/deltas.py")
deltas = importlib.util.module_from_spec(spec)
spec.loader.exec_module(deltas)


class ReleaseAssetPlanTests(unittest.TestCase):
    def plan(self, channel):
        version = "9.9.0-beta.1" if channel == "beta" else "9.9.0"
        with tempfile.TemporaryDirectory(prefix="release-assets-test-") as output:
            result = subprocess.run(
                ["bash", str(ROOT / "scripts/release/release.sh"), "--channel", channel,
                 "--version", version, "--identity", "-", "--plan", "--output", output],
                text=True, capture_output=True, check=True,
            )
        return result.stderr

    def test_single_app_download_and_two_deltas_in_every_channel(self):
        for channel in ("stable", "beta", "nightly"):
            with self.subTest(channel=channel):
                plan = self.plan(channel)
                self.assertIn("--maximum-deltas 2", plan)
                uploads = "\n".join(line for line in plan.splitlines()
                                    if "gh release create" in line or "gh release upload" in line)
                self.assertIn(".zip", uploads)
                self.assertNotIn(".dmg", uploads)
                self.assertNotIn("dSYMs", uploads)
                self.assertIn("native-host-", uploads)
                self.assertIn("appcast.xml", uploads)
                # Packaging checks stay intact even though the DMG isn't attached.
                self.assertIn("hdiutil create", plan)
                self.assertIn("stapler staple", plan)

    def test_only_stable_packs_celebration_icons(self):
        self.assertIn("celebration-assets.sh pack", self.plan("stable"))
        for channel in ("beta", "nightly"):
            with self.subTest(channel=channel):
                self.assertNotIn("celebration-assets.sh pack", self.plan(channel))

    def test_beta_still_refreshes_latest_stable_appcast(self):
        plan = self.plan("beta")
        self.assertIn("gh release upload \\<latest\\ stable\\ tag\\>", plan)
        self.assertIn("sentry.sh", plan)
        self.assertIn("[dry run] would run:", plan)


class DeltaAssetTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory(prefix="release-deltas-test-")
        self.root = Path(self.directory.name)
        self.appcast = self.root / "appcast.xml"
        self.prefix = "https://example.invalid/releases/download/v2/"

    def tearDown(self):
        self.directory.cleanup()

    def feed(self, current_deltas=(), old_deltas=()):
        def patches(names):
            return "".join(f'<enclosure url="{name}" sparkle:edSignature="patch-signature"/>'
                           for name in names)
        self.appcast.write_text(f'''<?xml version="1.0"?>
<rss xmlns:sparkle="{deltas.SPARKLE}"><channel>
<item><sparkle:version>2</sparkle:version><sparkle:channel>beta</sparkle:channel>
<description>&lt;p&gt;Release &amp; notes&lt;/p&gt;</description>
<enclosure url="{self.prefix}Native-2.zip" sparkle:edSignature="app-signature"/>
<sparkle:deltas>{patches(current_deltas)}</sparkle:deltas></item>
<item><sparkle:version>1</sparkle:version>
<enclosure url="https://example.invalid/releases/download/v1/Native-1.zip"
 sparkle:edSignature="old-signature"/>
<sparkle:deltas>{patches(old_deltas)}</sparkle:deltas></item>
</channel></rss>''')

    def patch_file(self, name):
        path = self.root / name
        path.write_bytes(b"delta fixture")
        return path

    def select(self):
        return deltas.select(self.appcast, "Native-2.zip", self.prefix, 2)

    def test_only_current_deltas_ship_without_changing_other_channel_downloads(self):
        current = self.patch_file("Native2-1.delta")
        unused = self.patch_file("Native1-0.delta")
        orphan = self.patch_file("unused.delta")
        remote = "https://example.invalid/releases/download/v1/Native1-0.delta"
        self.feed([self.prefix + current.name], [self.prefix + unused.name, remote])
        self.assertEqual(self.select(), [current])
        self.assertFalse(unused.exists())
        self.assertFalse(orphan.exists())
        items = ET.parse(self.appcast).findall("./channel/item")
        self.assertEqual(items[0].find("description").text, "<p>Release & notes</p>")
        self.assertEqual(items[0].find(f"{{{deltas.SPARKLE}}}channel").text, "beta")
        self.assertEqual(items[0].find("enclosure").get(f"{{{deltas.SPARKLE}}}edSignature"), "app-signature")
        self.assertEqual(items[1].find("enclosure").get("url"),
                         "https://example.invalid/releases/download/v1/Native-1.zip")
        self.assertEqual(items[1].find(f"{{{deltas.SPARKLE}}}deltas/enclosure").get("url"), remote)

    def test_no_seeds_uses_full_archive(self):
        self.feed()
        self.assertEqual(self.select(), [])
        self.assertEqual(len(ET.parse(self.appcast).findall("./channel/item/enclosure")), 2)

    def test_two_deltas_are_allowed_but_three_stop_publication(self):
        paths = [self.patch_file(f"Native2-{number}.delta") for number in range(3)]
        self.feed([self.prefix + path.name for path in paths[:2]])
        self.assertEqual(self.select(), paths[:2])
        self.patch_file(paths[2].name)
        self.feed([self.prefix + path.name for path in paths])
        before = self.appcast.read_bytes()
        with self.assertRaisesRegex(ValueError, "at most 2"):
            self.select()
        self.assertEqual(self.appcast.read_bytes(), before)
        self.assertTrue(all(path.exists() for path in paths))

    def test_missing_delta_stops_publication(self):
        self.feed([self.prefix + "missing.delta"])
        with self.assertRaisesRegex(ValueError, "missing"):
            self.select()

    def test_missing_current_archive_stops_publication(self):
        self.feed()
        with self.assertRaisesRegex(ValueError, "Expected one appcast item"):
            deltas.select(self.appcast, "wrong.zip", self.prefix, 2)

    def test_path_outside_artifacts_is_rejected(self):
        self.feed([self.prefix + "../outside.delta"])
        with self.assertRaisesRegex(ValueError, "Invalid local delta"):
            self.select()


class NightlyRetentionTests(unittest.TestCase):
    def obsolete(self, names, current=""):
        result = subprocess.run(
            ["bash", "-euo", "pipefail", "-c",
             'source "$1"; obsolete_nightly_assets Native-Nightly "$2"', "test",
             str(ROOT / "scripts/release/lib.sh"), f" {current} "],
            input="\n".join(names), text=True, capture_output=True, check=True,
        )
        return set(result.stdout.splitlines())

    def test_keeps_two_downloads_signed_feeds_and_only_current_deltas(self):
        keep = {"Native-Nightly-10.zip", "Native-Nightly-11.zip",
                "native-host-10-macos-universal", "native-host-11-macos-universal",
                "appcast.xml", "host-feed.json", "host-feed.json.sig", "Native-Nightly11-10.delta"}
        remove = {"Native-Nightly-9.zip", "native-host-9-macos-universal", "Native-Nightly.dmg",
                  "Native-Nightly10-9.delta", "celebration-christmas.json",
                  "celebration-assets.json", "celebration-assets.json.sig"}
        self.assertEqual(self.obsolete(sorted(keep | remove), "Native-Nightly11-10.delta"), remove)

    def test_empty_first_release_and_no_deltas_are_safe(self):
        self.assertEqual(self.obsolete([]), set())
        self.assertEqual(self.obsolete(["appcast.xml", "Native-Nightly-1.zip"]), set())


if __name__ == "__main__":
    unittest.main()
