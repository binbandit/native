#!/usr/bin/env python3
"""Prepare app sources and resolve declarations requested by Swift's diagnostics."""

import argparse
import re
from collections import defaultdict
from pathlib import Path


# App declarations are at column zero. Nested declarations must not satisfy an unrelated
# missing name. The compiler, rather than identifiers in comments or inactive code, asks for files.
DECLARATION = re.compile(
    r"^(?:@\w+(?:\([^\n]*?\))? +)*"
    r"(?:(?:public|internal|private|fileprivate|final|nonisolated|indirect|open|package) +)*"
    r"(?:struct|class|actor|enum|protocol|typealias|func|let|var) +(`?\w+`?)",
    re.MULTILINE,
)
EXTENSION = re.compile(r"^(?:(?:public|internal|private|fileprivate|nonisolated) +)*extension +(\w+)", re.MULTILINE)
MEMBER = re.compile(r"\b(?:func|var|let|typealias) +(`?\w+`?)")
MISSING_NAME = re.compile(r"error: cannot find (?:type )?'([^']+)' in scope")
MISSING_MEMBER = re.compile(r"error: .*has no (?:dynamic )?member '([^']+)'")


def strip_previews(text):
    start = 0
    while (preview := text.find("#Preview", start)) >= 0:
        opening = text.find("{", preview)
        if opening < 0:
            raise ValueError("#Preview has no body")
        depth = 0
        for end in range(opening, len(text)):
            depth += {"{": 1, "}": -1}.get(text[end], 0)
            if depth == 0:
                break
        else:
            raise ValueError("#Preview has an unclosed body")
        # Keep diagnostics at the original line numbers, including declarations below previews.
        replacement = "\n" * text[preview : end + 1].count("\n")
        text = text[:preview] + replacement + text[end + 1 :]
        start = preview + len(replacement)
    return text


def source_files(root, paths):
    result = set()
    for name in paths:
        path = (root / name).resolve()
        if not path.is_relative_to(root) or not path.exists():
            raise ValueError(f"{name}: no such folder or file in the repository")
        result.update([path] if path.is_file() and path.suffix == ".swift" else path.rglob("*.swift"))
    return {path.relative_to(root) for path in result}


def prepare(root, destination, paths=(), diagnostics=""):
    sources = {path.relative_to(root): path.read_text() for path in (root / "native").rglob("*.swift")}
    declarations, extensions, members = defaultdict(set), defaultdict(set), defaultdict(set)
    for path, text in sources.items():
        for name in DECLARATION.findall(text):
            declarations[name.strip("`")].add(path)
        for name in EXTENSION.findall(text):
            extensions[name].add(path)
            for member in MEMBER.findall(text):
                members[member.strip("`")].add(path)

    existing = {path.relative_to(destination) for path in destination.rglob("*.swift")}
    selected = existing | source_files(root, paths)
    for name in MISSING_NAME.findall(diagnostics):
        selected.update(declarations[name])
    for member in MISSING_MEMBER.findall(diagnostics):
        selected.update(members[member])

    # An app type's extensions are part of its API, even when kept in another feature folder.
    pending = list(selected)
    while pending:
        path = pending.pop()
        text = sources.get(path)
        if text is None:
            text = (root / path).read_text()
        for name in DECLARATION.findall(text):
            for extension in extensions[name.strip("`")] - selected:
                selected.add(extension)
                pending.append(extension)

    added = sorted(selected - existing)
    for path in added:
        target = destination / path
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_text(strip_previews((root / path).read_text()))
    return added


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("destination", type=Path)
    parser.add_argument("paths", nargs="*")
    parser.add_argument("--diagnostics", type=Path)
    args = parser.parse_args()
    try:
        diagnostics = args.diagnostics.read_text() if args.diagnostics else ""
        added = prepare(Path.cwd().resolve(), args.destination, args.paths, diagnostics)
    except ValueError as error:
        parser.exit(2, f"{error}\n")
    for path in added:
        print(path)


if __name__ == "__main__":
    main()
