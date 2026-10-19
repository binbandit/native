#!/usr/bin/env python3
"""Says where an executable's bytes come from, from the linker's map of it (docs/app-size.md).

    scripts/release/release.sh --channel stable --version 0.0.1 --build-setting LD_GENERATE_MAP_FILE=YES
    python3 -I scripts/release/linkmap.py <Native-LinkMap-normal-arm64.txt> [--top 25]

Sums every symbol's size per library (a static archive or framework), Swift package module, or
folder of the app's own code (native/<Folder>), split into __TEXT,__text (code) and __TEXT,__const
(constant data, such as tree-sitter's parse tables), largest first. The archive's map is under
DerivedData/Build/Intermediates.noindex/ArchiveIntermediates/native/IntermediateBuildFilesPath/
native.build/Release/native.build/.
"""
import argparse
import bisect
import collections
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]


def parse(path):
    files, sections, symbols, part = {}, [], [], None
    with open(path, errors='replace') as lines:
        for line in lines:
            if line.startswith('# Object files:'):
                part = 'files'
            elif line.startswith('# Sections:'):
                part = 'sections'
            elif line.startswith('# Symbols:'):
                part = 'symbols'
            elif line.startswith('# Dead Stripped Symbols:'):
                break
            elif not line.startswith('#'):
                if part == 'files' and (m := re.match(r'\[\s*(\d+)\]\s+(.*)', line)):
                    files[int(m[1])] = m[2].strip()
                elif part == 'sections' and len(fields := line.split()) >= 4:
                    sections.append((int(fields[0], 16), int(fields[1], 16), f'{fields[2]},{fields[3]}'))
                elif part == 'symbols' and (m := re.match(r'(0x[0-9A-F]+)\s+(0x[0-9A-F]+)\s+\[\s*(\d+)\]', line)):
                    symbols.append((int(m[1], 16), int(m[2], 16), int(m[3])))
    return files, sections, symbols


def group_of(path, app_folders):
    if m := re.search(r'([^/]+\.framework)/[^/(]+\(', path):
        return m[1]
    if m := re.search(r'([^/]+\.(?:a|rlib))\(', path):
        return m[1]
    if '/native.build/' in path and (m := re.search(r'/Objects-normal/[^/]+/([^/]+)\.o$', path)):
        return 'native/' + app_folders.get(m[1], '?')
    if m := re.search(r'/(?:BuildProductsPath|Products)/[^/]+/([^/]+)\.o$', path):
        return 'package ' + m[1]
    return path.rsplit('/', 1)[-1]


def main():
    arguments = argparse.ArgumentParser(description=__doc__.split('\n')[0])
    arguments.add_argument('map')
    arguments.add_argument('--top', type=int, default=25)
    options = arguments.parse_args()

    # The app target compiles one object per Swift file; name them by their folder.
    app_folders = {}
    for source in (ROOT / 'native').rglob('*.swift'):
        parts = source.relative_to(ROOT / 'native').parts
        app_folders[source.stem] = parts[0] if len(parts) > 1 else '(root)'

    files, sections, symbols = parse(options.map)
    starts = [start for start, _, _ in sections]
    totals = collections.defaultdict(collections.Counter)
    for address, size, index in symbols:
        i = bisect.bisect_right(starts, address) - 1
        section = sections[i][2] if i >= 0 and address < sections[i][0] + sections[i][1] else '?'
        counter = totals[group_of(files.get(index, '?'), app_folders)]
        counter[section] += size
        counter['all'] += size

    def mb(count):
        return f'{count / 1e6:8.2f}'

    print(f'{"":44} {"code":>8} {"const":>8} {"all":>8}  MB')
    ranked = sorted(totals.items(), key=lambda item: -item[1]['all'])
    for name, counter in ranked[:options.top]:
        print(f'{name[:44]:44} {mb(counter["__TEXT,__text"])} {mb(counter["__TEXT,__const"])} {mb(counter["all"])}')
    total = sum(totals.values(), collections.Counter())
    print(f'{"total":44} {mb(total["__TEXT,__text"])} {mb(total["__TEXT,__const"])} {mb(total["all"])}')


if __name__ == '__main__':
    main()
