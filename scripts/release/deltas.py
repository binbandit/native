#!/usr/bin/env python3
"""Select this release's Sparkle deltas and discard unused generated patches.

generate_appcast can also generate patches between the downloaded seed archives. Those
are not updates to this release, so older items use their existing remote patches or full archive.
Print the selected local paths for release.sh; never contact a publishing service.
"""

from pathlib import Path
import sys
from urllib.parse import unquote
import xml.etree.ElementTree as ET


SPARKLE = "http://www.andymatuschak.org/xml-namespaces/sparkle"
ET.register_namespace("sparkle", SPARKLE)
ET.register_namespace("dc", "http://purl.org/dc/elements/1.1/")


def select(appcast, archive, prefix, limit):
    tree = ET.parse(appcast)
    items = tree.findall("./channel/item")
    current = [item for item in items
               if item.find("enclosure") is not None
               and item.find("enclosure").get("url") == prefix + archive]
    if len(current) != 1:
        raise ValueError(f"Expected one appcast item for {archive}, found {len(current)}")

    selected = []
    changed = False
    for item in items:
        deltas = item.find(f"{{{SPARKLE}}}deltas")
        if deltas is None:
            continue
        for enclosure in list(deltas):
            url = enclosure.get("url", "")
            if not url.startswith(prefix):
                continue
            name = unquote(url[len(prefix):])
            if Path(name).name != name or not name.endswith(".delta"):
                raise ValueError(f"Invalid local delta name: {name}")
            if item is current[0]:
                path = appcast.parent / name
                if not path.is_file():
                    raise ValueError(f"Appcast delta is missing: {name}")
                selected.append(path)
            else:
                deltas.remove(enclosure)
                changed = True
        if not len(deltas):
            item.remove(deltas)
            changed = True

    if len(selected) > limit:
        raise ValueError(f"Expected at most {limit} deltas, found {len(selected)}")
    if changed:
        tree.write(appcast, encoding="utf-8", xml_declaration=True)
    for path in appcast.parent.glob("*.delta"):
        if path not in selected:
            path.unlink()
    return selected


if __name__ == "__main__":
    try:
        for path in select(Path(sys.argv[1]), sys.argv[2], sys.argv[3], int(sys.argv[4])):
            print(path)
    except (ValueError, ET.ParseError) as error:
        sys.exit(str(error))
