"""Focused checks for foreground queueing and source-based preview rendering."""
import importlib.util
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[3]
SPEC = importlib.util.spec_from_file_location("previews", ROOT / "scripts/dev/render-previews.py")
PREVIEWS = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(PREVIEWS)


class PreviewSourceTests(unittest.TestCase):
    def test_bodies_keep_private_helpers_and_nested_strings(self):
        source = '''import SwiftUI
private struct Sample: View { var body: some View { Text("{sample}") } }
// #Preview("not a preview") { }
#if DEBUG
#Preview("Empty") { VStack { Sample(); Text("}") } }
#Preview { Sample() }
#endif
'''
        rewritten, entries = PREVIEWS.preview_functions(source)
        self.assertEqual([name for _, name in entries], ["Empty", "nativeRenderedPreview1"])
        self.assertIn('private struct Sample', rewritten)
        self.assertIn('VStack { Sample(); Text("}") }', rewritten)
        self.assertIn('@MainActor @ViewBuilder func nativeRenderedPreview1()', rewritten)

    def test_support_comments_and_strings_do_not_consume_declarations(self):
        source = '''// Shared by #Preview fixtures.
struct Fixture { static let title = "Example #Preview { value }" }
/* #Preview("Comment") { ignored } */
#Preview("Actual") { Text(Fixture.title) }
func afterPreview() { }
'''
        stripped, _ = PREVIEWS.preview_functions(source, strip=True)
        self.assertIn('struct Fixture { static let title = "Example #Preview { value }" }', stripped)
        self.assertIn('func afterPreview() { }', stripped)
        self.assertNotIn('Text(Fixture.title)', stripped)
        fixture = (ROOT / "native/NewTask/QuickEntryPreviewFixtures.swift").read_text()
        self.assertIn('func applyLaunchState', PREVIEWS.preview_functions(fixture, strip=True)[0])

    def test_unsupported_preview_is_explicit(self):
        for source in ['#Preview(traits: .sizeThatFitsLayout) { Text("a") }',
                       '#Preview { @Previewable @State var value = false; Text("a") }']:
            with self.assertRaises(ValueError):
                PREVIEWS.preview_functions(source)


class BuildSlotTests(unittest.TestCase):
    def test_waiters_print_once_and_keep_order(self):
        with tempfile.TemporaryDirectory(prefix="native-build-slot-test-") as directory:
            root = Path(directory)
            script = root / "build-slot.sh"
            script.write_text((ROOT / "scripts/dev/build-slot.sh").read_text().replace(
                'slots=/tmp/native-build-slots', f'slots="{root}/slots"').replace('sleep 5', 'sleep 0.05'))
            script.chmod(0o755)
            xcode = root / "xcodebuild"
            xcode.write_text('#!/bin/bash\necho started\nread -r value < "$1"\n')
            xcode.chmod(0o755)
            env = dict(os.environ, PATH=f"{root}:" + os.environ['PATH'],
                       NATIVE_BUILD_SLOTS="1", NATIVE_BUILD_MIN_FREE_GB="0")
            processes = []
            try:
                for index in range(3):
                    gate = root / f"gate{index}"
                    os.mkfifo(gate)
                    process = subprocess.Popen([str(script), str(gate)], env=env, text=True,
                                               stdout=subprocess.PIPE, stderr=subprocess.PIPE)
                    processes.append(process)
                    if index == 0:
                        self.assertEqual(process.stdout.readline().strip(), "started")
                    else:
                        self.assertIn("waiting for a build slot:", process.stderr.readline())
                for index, process in enumerate(processes):
                    if index:
                        self.assertEqual(process.stdout.readline().strip(), "started")
                    with (root / f"gate{index}").open("w") as gate:
                        gate.write("done\n")
                    stdout, stderr = process.communicate(timeout=15)
                    self.assertEqual(process.returncode, 0, stderr)
                    self.assertNotIn("waiting for a build slot:", stderr)
            finally:
                for process in processes:
                    if process.poll() is None:
                        process.terminate()
                        process.wait(timeout=5)


if __name__ == "__main__":
    unittest.main()
