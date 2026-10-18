#!/bin/bash
# Builds Native's celebration icon assets from the artwork in design/app-icon/celebrations/<edition>/
# (docs/celebrations-artwork.md):
#
#   scripts/release/celebration-assets.sh thumbnails
#       Regenerates the small chooser thumbnails the app bundles (Regular light and dark, 128 px)
#       into native/Celebrations/CelebrationThumbnails.xcassets. Run after artwork changes; commit them.
#
#   CELEBRATION_ASSETS_SIGN="<command>" scripts/release/celebration-assets.sh pack <out-dir> [version]
#       Writes one pack per edition (celebration-<edition>.json: every channel's light and dark icon),
#       the index celebration-assets.json (each pack's SHA-256 and size) and its signature
#       celebration-assets.json.sig, for uploading to the release beside the app. The sign command
#       gets the index's path as its last argument and must print its base64 Ed25519 signature with
#       the update key (Sparkle's `sign_update -p --disable-signing-warning`), so the app verifies packs with the key it
#       already trusts.
#
#   scripts/release/celebration-assets.sh holidays <public-holidays.json>
#       Regenerates FirstPartyCelebrations+PublicHolidays.swift (the "Turn On a Country's Holidays"
#       data) from researched official calendars: {"countries": {"US": {"authority", "source",
#       "holidays": [edition slugs]}}}. Only statutory, nationwide public holidays belong in it.
#       The researched data, with notes and sources, is scripts/release/data/public-holidays.json.
#
# Editions in PENDING are left out until their artwork is chosen or delivered; EXCLUDED never ship.
set -euo pipefail

root=$(git -C "$(dirname "$0")" rev-parse --show-toplevel)
art="$root/design/app-icon/celebrations"
PENDING=(personal-celebration)
# Never shipped: artwork that imitates another culture's art form isn't Native's to use.
EXCLUDED=(australia-day-ochre-dots)
CHANNELS=(stable beta nightly dev)

editions() {
    for dir in "$art"/*/; do
        slug=$(basename "$dir")
        [[ " ${PENDING[*]} ${EXCLUDED[*]} " == *" $slug "* ]] && continue
        complete=1
        for channel in "${CHANNELS[@]}"; do
            for appearance in light dark; do
                [ -f "$dir/$channel-$appearance.png" ] || { echo "skipping $slug: no $channel-$appearance.png" >&2; complete=0; }
            done
        done
        [ "$complete" = 1 ] && echo "$slug"
    done
}

thumbnails() {
    local catalog="$root/native/Celebrations/CelebrationThumbnails.xcassets"
    rm -rf "$catalog"
    mkdir -p "$catalog"
    printf '{\n  "info" : {\n    "author" : "xcode",\n    "version" : 1\n  }\n}\n' >"$catalog/Contents.json"
    for slug in $(editions); do
        for appearance in light dark; do
            local set="$catalog/CelebrationThumbnail-$slug-$appearance.imageset"
            mkdir -p "$set"
            sips -s format png -Z 128 "$art/$slug/stable-$appearance.png" --out "$set/thumbnail.png" >/dev/null
            printf '{\n  "images" : [\n    {\n      "filename" : "thumbnail.png",\n      "idiom" : "universal"\n    }\n  ],\n  "info" : {\n    "author" : "xcode",\n    "version" : 1\n  }\n}\n' >"$set/Contents.json"
        done
    done
    du -sh "$catalog"
}

pack() {
    local out=${1:?usage: pack <out-dir> [version]}
    local version=${2:-$(date -u +%Y.%m.%d)}
    : "${CELEBRATION_ASSETS_SIGN:?set CELEBRATION_ASSETS_SIGN to a command that prints the base64 Ed25519 signature of a file}"
    mkdir -p "$out"
    # A clean slate, so a pack dropped since the last run (an excluded edition) is never uploaded.
    rm -f "$out"/celebration-*.json "$out/celebration-assets.json.sig"
    # shellcheck disable=SC2046
    python3 -I - "$art" "$out" "$version" $(editions) <<'PY'
import base64, hashlib, json, os, sys
art, out, version, editions = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4:]
packs = {}
for slug in editions:
    images = {}
    for channel in ("stable", "beta", "nightly", "dev"):
        for appearance in ("light", "dark"):
            with open(os.path.join(art, slug, f"{channel}-{appearance}.png"), "rb") as png:
                images[f"{channel}-{appearance}"] = base64.b64encode(png.read()).decode()
    data = json.dumps({"schema": 1, "edition": slug, "images": images}, sort_keys=True).encode()
    name = f"celebration-{slug}.json"
    with open(os.path.join(out, name), "wb") as f:
        f.write(data)
    packs[slug] = {"file": name, "sha256": hashlib.sha256(data).hexdigest(), "size": len(data)}
with open(os.path.join(out, "celebration-assets.json"), "w") as f:
    json.dump({"schema": 1, "version": version, "packs": packs}, f, sort_keys=True, indent=1)
print(f"{len(packs)} packs, version {version}")
PY
    # shellcheck disable=SC2086
    $CELEBRATION_ASSETS_SIGN "$out/celebration-assets.json" | tr -d '\n' >"$out/celebration-assets.json.sig"
    [ -s "$out/celebration-assets.json.sig" ] || { echo "the sign command printed nothing" >&2; exit 1; }
    du -sh "$out"
}

holidays() {
    local input=${1:?usage: holidays <public-holidays.json>}
    python3 -I - "$input" "$root/Packages/AppAppearance/Sources/AppAppearance/Celebrations/FirstPartyCelebrations+PublicHolidays.swift" <<'PY'
import json, sys
data, out = json.load(open(sys.argv[1])), sys.argv[2]
q = lambda s: json.dumps(s, ensure_ascii=False)
rows = []
for code, entry in sorted(data["countries"].items()):
    slugs = ", ".join(q(s) for s in sorted(set(entry["holidays"])))
    rows.append(f"        {q(code)}: PublicHolidayCalendar(\n            authority: {q(entry['authority'])},\n"
                f"            source: {q(entry['source'])},\n            holidays: [{slugs}]),")
body = "\n".join(rows) if rows else ""
text = f"""// Generated by scripts/release/celebration-assets.sh holidays from official public-holiday
// calendars. Only statutory, nationwide public holidays count, never "widely celebrated"; a country
// without an official source is left out. Regenerate rather than editing by hand.

extension FirstPartyCelebrations {{
    /// Each country's official calendar and the catalogue's celebrations that are public holidays
    /// there, by ISO 3166-1 alpha-2 code.
    static let publicHolidayCalendars: [String: PublicHolidayCalendar] = [
{body}
    ]
}}

/// Where one country's public holidays come from.
struct PublicHolidayCalendar {{
    let authority: String
    let source: String
    /// Edition slugs (the celebration id without `native.`).
    let holidays: Set<String>
}}
"""
open(out, "w").write(text.replace("[\n\n    ]", "[:]"))
print(f"{len(rows)} countries")
PY
}

case "${1:-}" in
thumbnails) thumbnails ;;
holidays) shift; holidays "$@" ;;
pack) shift; pack "$@" ;;
*) sed -n '2,20p' "$0"; exit 2 ;;
esac
