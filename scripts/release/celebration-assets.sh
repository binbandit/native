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
#       the update key (Sparkle's `sign_update -p`), so the app verifies packs with the key it
#       already trusts.
#
# Editions in PENDING are left out until their artwork is chosen.
set -euo pipefail

root=$(git -C "$(dirname "$0")" rev-parse --show-toplevel)
art="$root/design/app-icon/celebrations"
PENDING=(personal-celebration)
CHANNELS=(stable beta nightly dev)

editions() {
    for dir in "$art"/*/; do
        slug=$(basename "$dir")
        [[ " ${PENDING[*]} " == *" $slug "* ]] && continue
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

case "${1:-}" in
thumbnails) thumbnails ;;
pack) shift; pack "$@" ;;
*) sed -n '2,20p' "$0"; exit 2 ;;
esac
