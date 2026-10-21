import importlib.util
import os
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path


spec = importlib.util.spec_from_file_location("check_ios_sources", Path(__file__).parents[1] / "check-ios-sources.py")
sources = importlib.util.module_from_spec(spec)
spec.loader.exec_module(sources)


class CheckIOSSourcesTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name).resolve()
        self.destination = self.root / "prepared"

    def write(self, path, text):
        file = self.root / path
        file.parent.mkdir(parents=True, exist_ok=True)
        file.write_text(text)

    def test_missing_model_brings_extensions_and_transitive_declarations(self):
        self.write("native/Views/Screen.swift", "struct Screen { let model: Model }\n")
        self.write("native/Models/Model.swift", "final class Model { let key: Key }\n")
        self.write("native/Feature/Model+Action.swift", "extension Model { func act() {} }\n")
        self.write("native/Models/Key.swift", "nonisolated struct Key {}\n")
        self.write("native/Unrelated/MacOnly.swift", "import AppKit\nstruct MacOnly {}\n")
        sources.prepare(self.root, self.destination, ["native/Views"])
        added = sources.prepare(self.root, self.destination, diagnostics="error: cannot find type 'Model' in scope")
        self.assertEqual(set(added), {Path("native/Models/Model.swift"), Path("native/Feature/Model+Action.swift")})
        added = sources.prepare(self.root, self.destination, diagnostics="error: cannot find type 'Key' in scope")
        self.assertEqual(added, [Path("native/Models/Key.swift")])
        self.assertFalse((self.destination / "native/Unrelated/MacOnly.swift").exists())

    def test_explicit_model_includes_extensions_without_diagnostics(self):
        self.write("native/Models/Model.swift", "final class Model {}\n")
        self.write("native/Feature/Model+Action.swift", "extension Model { func act() {} }\n")
        added = sources.prepare(self.root, self.destination, ["native/Models", "native/Models/Model.swift"])
        self.assertEqual(len(added), 2)
        self.assertEqual(sources.prepare(self.root, self.destination, ["native/Models"]), [])

    def test_nested_declaration_cannot_supply_missing_top_level_type(self):
        self.write("native/Feature/Outer.swift", "struct Outer {\n    struct Missing {}\n}\n")
        self.assertEqual(
            sources.prepare(self.root, self.destination, diagnostics="error: cannot find type 'Missing' in scope"), []
        )

    def test_actor_and_same_line_attribute_declarations(self):
        self.write("native/Feature/Worker.swift", "actor Worker {}\n")
        self.write("native/Feature/Service.swift", "@MainActor final class Service {}\n")
        added = sources.prepare(
            self.root, self.destination,
            diagnostics="error: cannot find 'Worker' in scope\nerror: cannot find type 'Service' in scope",
        )
        self.assertEqual(len(added), 2)

    def test_missing_global_function_and_sdk_extension(self):
        self.write("native/Feature/Helper.swift", "func helper() {}\n")
        self.write("native/Platform/View+Action.swift", "extension View {\n    func actionModifier() -> some View { self }\n}\n")
        added = sources.prepare(
            self.root,
            self.destination,
            diagnostics="error: cannot find 'helper' in scope\nerror: value of type 'some View' has no member 'actionModifier'",
        )
        self.assertEqual(set(added), {Path("native/Feature/Helper.swift"), Path("native/Platform/View+Action.swift")})

    def test_local_variables_do_not_supply_missing_members(self):
        self.write(
            "native/Unrelated/Extension.swift",
            "import AppKit\nextension String {\n    func helper() {\n        let missing = 1\n    }\n}\n"
            "struct Unrelated {\n    var missing: Int\n}\n",
        )
        self.assertEqual(
            sources.prepare(self.root, self.destination, diagnostics="error: value of type 'View' has no member 'missing'"), []
        )

    def test_inline_attributes_on_direct_extension_members(self):
        self.write(
            "native/Settings/FocusedValues.swift",
            "extension FocusedValues {\n    @Entry var activeSession: Model?\n}\n",
        )
        self.assertEqual(
            sources.prepare(
                self.root, self.destination,
                diagnostics="error: value of type 'FocusedValues' has no member 'activeSession'",
            ),
            [Path("native/Settings/FocusedValues.swift")],
        )

    def test_real_platform_error_does_not_add_unrelated_sources(self):
        self.write("native/Models/Model.swift", "class Model {}\n")
        self.assertEqual(
            sources.prepare(self.root, self.destination, diagnostics="Screen.swift:1:8: error: no such module 'AppKit'"), []
        )

    def test_preview_removal_preserves_lines_after_multiple_previews(self):
        text = 'struct Before {}\n#Preview("First") {\n    View { Text("Hi") }\n}\n#Preview { Text("Bye") }\nstruct After {}\n'
        prepared = sources.strip_previews(text)
        self.assertNotIn("#Preview", prepared)
        self.assertEqual(prepared.splitlines().index("struct After {}"), text.splitlines().index("struct After {}"))

    def test_missing_or_outside_paths_are_rejected(self):
        self.write("native/Feature/View.swift", "struct View {}\n")
        for path in ["native/Missing", "../"]:
            with self.subTest(path=path), self.assertRaises(ValueError):
                sources.prepare(self.root, self.destination, [path])


@unittest.skipUnless(os.environ.get("NATIVE_IOS_CHECK_INTEGRATION") == "1", "set NATIVE_IOS_CHECK_INTEGRATION=1 for the iOS compiler")
class CheckIOSIntegrationTests(unittest.TestCase):
    setUp = CheckIOSSourcesTests.setUp
    write = CheckIOSSourcesTests.write

    def test_cli_resolves_app_and_package_dependencies_and_keeps_real_errors(self):
        subprocess.run(["git", "init", "-q", str(self.root)], check=True)
        scripts = self.root / "scripts"
        scripts.mkdir()
        for name in ["check-ios.sh", "check-ios-sources.py"]:
            shutil.copy2(Path(__file__).parents[1] / name, scripts / name)
        self.write("native/DesignSystem/Token+Values.swift", "enum Token {}\n")
        self.write("native/Views/Screen.swift", "struct Screen { let model: Model; func read() -> Int { model.value() } }\n")
        self.write("native/Models/Model.swift", "#if os(macOS)\nimport HostOnly\n#else\nimport LocalSupport\n#endif\nstruct Model { let data: Payload }\n")
        self.write("native/Feature/Model+Value.swift", "import LocalSupport\nextension Model { func value() -> Int { data.number } }\n")
        self.write(
            "Packages/LocalSupport/Package.swift",
            '// swift-tools-version: 6.2\nimport PackageDescription\n'
            'let package = Package(name: "LocalSupport", targets: [.target(name: "LocalSupport"), '
            '.testTarget(name: "LocalSupportTests", resources: [.copy("Fixtures")])])\n',
        )
        self.write("Packages/LocalSupport/Tests/LocalSupportTests/Fixtures/data.json", "{}\n")
        self.write("Packages/LocalSupport/Sources/LocalSupport/Payload.swift", "public struct Payload { public let number: Int }\n")
        self.write(
            "Packages/HostOnly/Package.swift",
            '// swift-tools-version: 6.2\nimport PackageDescription\n'
            'let package = Package(name: "HostOnly", platforms: [.macOS(.v15)], targets: [.target(name: "HostOnly")])\n',
        )
        self.write("Packages/HostOnly/Sources/HostOnly/Host.swift", "import AppKit\n")
        self.write("native/Unrelated/MacOnly.swift", "import AppKit\nstruct MacOnly {}\n")
        command = ["bash", "check-ios.sh", "native/Views", "native/Views/Screen.swift"]
        result = subprocess.run(command, cwd=scripts, text=True, capture_output=True)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn("iOS check passed", result.stdout)
        self.assertIn("Including", result.stderr)

        self.write(
            "native/Views/Screen.swift",
            "#if canImport(LocalSupport)\nimport LocalSupport\nstruct Screen { let broken: NotARealType }\n#endif\n"
            '#if canImport(AppKit) || canImport(HostOnly)\n#error("macOS branch must remain inactive")\n#endif\n',
        )
        result = subprocess.run(command, cwd=scripts, text=True, capture_output=True)
        self.assertNotEqual(result.returncode, 0, "local package availability must not skip the consumer")
        self.assertIn("cannot find type 'NotARealType' in scope", result.stdout)
        self.assertNotIn("macOS branch must remain inactive", result.stdout)

        self.write("native/Views/Screen.swift", "struct Screen { let model: Model }\n")
        self.write("native/Models/Model.swift", "import AppKit\nstruct Model {}\n")
        result = subprocess.run(command, cwd=scripts, text=True, capture_output=True)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn(f"{self.root}/native/Models/Model.swift:1:8: error: no such module 'AppKit'", result.stdout)
        self.assertNotIn("iOS check passed", result.stdout)


if __name__ == "__main__":
    unittest.main()
