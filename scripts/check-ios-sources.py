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
MEMBER = re.compile(
    r"^    (?:@\w+(?:\([^\n]*?\))? +)*"
    r"(?:(?:public|internal|private|fileprivate|static|class|nonisolated|mutating) +)*"
    r"(?:func|var|let|typealias) +(`?\w+`?)",
    re.MULTILINE,
)
# A property wrapper or attached macro that isn't in yet reads as an unknown attribute.
MISSING_NAME = re.compile(r"error: (?:cannot find (?:type )?'([^']+)' in scope|unknown attribute '([^']+)')")
# An implicit member (`.buttonStyle(.settings)`) whose declaration isn't in yet can't be resolved.
MISSING_MEMBER = re.compile(
    r"error: .*(?:has no (?:dynamic )?member '([^']+)'|reference to member '([^']+)' cannot be resolved)"
)
MISSING_CONFORMANCE = re.compile(
    r"(?:argument )?type '([^']+)' does not conform to (?:expected type|specified type|protocol) '([^']+)'"
    r"|requires that '([^']+)' conform to '([^']+)'"
)


# Braces inside string literals and comments (sample code in a preview) don't open or close blocks.
SKIPPED = re.compile(r'(#*)"""(?:\\.|[^\\])*?"""\1|(#*)"(?:\\.|[^"\\\n])*"\2|//[^\n]*|/\*.*?\*/', re.DOTALL)


def matching_brace(text, opening):
    depth = 0
    position = opening
    while position < len(text):
        if skipped := SKIPPED.match(text, position):
            position = skipped.end()
            continue
        depth += {"{": 1, "}": -1}.get(text[position], 0)
        if depth == 0:
            return position
        position += 1
    return None


def strip_previews(text):
    start = 0
    while (preview := text.find("#Preview", start)) >= 0:
        opening = text.find("{", preview)
        if opening < 0:
            raise ValueError("#Preview has no body")
        end = matching_brace(text, opening)
        if end is None:
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
    conformances = defaultdict(set)
    for path, text in sources.items():
        for name in DECLARATION.findall(text):
            declarations[name.strip("`")].add(path)
        for extension in EXTENSION.finditer(text):
            extensions[extension[1]].add(path)
            header = text[extension.end():text.find("{", extension.end())].split("where", 1)[0]
            if ":" in header:
                extended_type = re.match(r"[\w.]+", text[extension.start(1):])[0]
                inherited = header.split(":", 1)[1]
                for protocol in re.findall(r"(?:^|,)\s*(?:@\w+\s+)*([\w.]+)", inherited):
                    conformances[extended_type, protocol.rsplit(".", 1)[-1]].add(path)
            # The repository's formatter closes a top-level extension at column zero. Limit
            # candidates to its direct members, not locals or other types in the same file.
            closing = re.search(r"^}", text[extension.end():], re.MULTILINE)
            body = text[extension.end():extension.end() + closing.end()] if closing else text[extension.end():]
            for member in MEMBER.findall(body):
                members[member.strip("`")].add(path)

    existing = {path.relative_to(destination) for path in destination.rglob("*.swift")}
    selected = existing | source_files(root, paths)
    missing_names = [match[1] or match[2] for match in MISSING_NAME.finditer(diagnostics)]
    for name in missing_names:
        selected.update(declarations[name])
    # Missing type context can also make its properties look like unresolved bare names. Resolve
    # declarations first; only a later pass should look for unqualified extension members.
    if selected == existing:
        for name in missing_names:
            selected.update(members[name])
    for member in (match[1] or match[2] for match in MISSING_MEMBER.finditer(diagnostics)):
        selected.update(members[member])
    for match in MISSING_CONFORMANCE.finditer(diagnostics):
        type_name, protocol = match.group(1, 2) if match[1] else match.group(3, 4)
        type_name = re.sub(r"<.*>", "", type_name)
        protocol = protocol.removeprefix("any ").rsplit(".", 1)[-1]
        for candidate in (type_name, type_name.partition(".")[2], type_name.rsplit(".", 1)[-1]):
            selected.update(conformances[candidate, protocol])

    # Keep a type's local implementation together. Extensions in other features are consumers too:
    # including them eagerly drags the whole app into independent DesignSystem/Platform checks.
    # Cross-folder members are added only when diagnostics request them above.
    pending = list(selected)
    while pending:
        path = pending.pop()
        text = sources.get(path)
        if text is None:
            text = (root / path).read_text()
        for name in DECLARATION.findall(text):
            for extension in extensions[name.strip("`")] - selected:
                if extension.parent != path.parent:
                    continue
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
