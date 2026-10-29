#!/usr/bin/env python3
"""Render a view's #Preview bodies without building or launching Native."""

import argparse
import importlib.util
import json
from pathlib import Path
import re
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[2]
SPEC = importlib.util.spec_from_file_location("sources", ROOT / "scripts/check-ios-sources.py")
SOURCES = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(SOURCES)


def preview_functions(text):
    """Keep each body beside its private helpers, replacing only the macro header."""
    names = []
    result = []
    position = 0
    start = 0
    while position < len(text):
        if skipped := SOURCES.SKIPPED.match(text, position):
            position = skipped.end()
            continue
        if not text.startswith("#Preview", position):
            position += 1
            continue
        opening = position + len("#Preview")
        depth = 0
        while opening < len(text):
            if skipped := SOURCES.SKIPPED.match(text, opening):
                opening = skipped.end()
                continue
            character = text[opening]
            if character == "{" and depth == 0:
                break
            depth += {"(": 1, ")": -1}.get(character, 0)
            opening += 1
        end = SOURCES.matching_brace(text, opening)
        if end is None:
            raise ValueError("#Preview has no complete body")
        header = text[position:opening]
        if re.search(r"\btraits\s*:", header) or "@Previewable" in text[opening:end]:
            raise ValueError("preview traits and @Previewable require Xcode or a full-app check")
        label = re.search(r'"([^"\n]*)"', header)
        name = f"nativeRenderedPreview{len(names)}"
        names.append((name, label[1] if label else name))
        result.append(text[start:position])
        result.append(f"@MainActor @ViewBuilder func {name}() -> some View ")
        result.append(text[opening:end + 1])
        position = start = end + 1
    result.append(text[start:])
    if not names:
        raise ValueError("selected source has no #Preview bodies")
    return "".join(result), names


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("view", type=Path)
    parser.add_argument("output", type=Path)
    parser.add_argument("--support", action="append", default=[])
    parser.add_argument("--width", type=int, default=800)
    parser.add_argument("--height", type=int, default=600)
    args = parser.parse_args()
    if args.width <= 0 or args.height <= 0:
        parser.error("width and height must be positive")
    try:
        view = args.view.resolve()
        SOURCES.source_files(ROOT, [str(view)])
        rewritten, previews = preview_functions(view.read_text())
        support = SOURCES.source_files(ROOT, args.support) - {view.relative_to(ROOT)}
    except ValueError as error:
        parser.error(str(error))
    cache = Path.home() / "Library/Caches/native-build/previews"
    cache.mkdir(parents=True, exist_ok=True)
    args.output.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix="native-previews-") as directory:
        work = Path(directory)
        bundle = work / "PreviewRender.app"
        resources = bundle / "Contents/Resources"
        resources.mkdir(parents=True)
        for font in (ROOT / "native/DesignSystem/Fonts").glob("*.ttf"):
            shutil.copy2(font, resources)
        import plistlib
        with (bundle / "Contents/Info.plist").open("wb") as file:
            plistlib.dump({"CFBundleIdentifier": "dev.binbandit.native.dev.preview-render",
                          "CFBundleExecutable": "preview-render"}, file)
        inputs = []
        for index, (path, text) in enumerate([(view, rewritten)] + [
            (ROOT / path, SOURCES.strip_previews((ROOT / path).read_text())) for path in sorted(support)
        ]):
            staged = work / f"source{index}.swift"
            staged.write_text(f"#sourceLocation(file: {json.dumps(str(path))}, line: 1)\n" + text)
            inputs.append(str(staged))
        entries = ",\n".join(f"({json.dumps(label, ensure_ascii=False)}, {{ AnyView({name}()) }})"
                             for name, label in previews)
        runner = work / "runner.swift"
        runner.write_text((ROOT / "scripts/dev/render-previews.swift").read_text().replace(
            'fatalError("PREVIEW_ENTRIES")', "return [\n" + entries + "\n]"))
        executable = bundle / "Contents/MacOS/preview-render"
        executable.parent.mkdir()
        subprocess.run(["nice", "-n", "10", "xcrun", "swiftc", "-parse-as-library", "-swift-version", "6",
                        "-default-isolation", "MainActor", "-D", "DEBUG", "-D", "NATIVE_PREVIEWS_WIP",
                        "-module-cache-path", str(cache / "ModuleCache.noindex"), *inputs, str(runner),
                        "-o", str(executable)], check=True)
        subprocess.run([str(executable), str(args.output.resolve()), str(args.width), str(args.height),
                        "-sounds.enabled", "NO", "-native.mute", "YES"], check=True)


if __name__ == "__main__":
    try:
        main()
    except subprocess.CalledProcessError as error:
        raise SystemExit(error.returncode) from None
