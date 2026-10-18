#!/bin/bash
# Builds the iPhone app's alternate icons from the icon work's documents in design/app-icon
# (docs/companion.md, "App icons"). The companion target runs it before compiling resources; its
# output, Companion/AppIcons/, is a build product: gitignored, never committed. Nothing here draws
# or edits artwork.
#
#   scripts/companion/app-icons.sh [--force]
#
# - The five themes stay layered: their Regular stable.icon documents are copied as
#   AppIcon-<theme>.icon, and Xcode compiles light, dark, tinted and clear from each.
# - Every celebration edition and style is flat: Icon Composer's ictool renders its Regular
#   stable.icon in light and dark at the iPhone icon sizes, into
#   CelebrationIcons.xcassets/AppIcon-<edition>.appiconset. Layered, the 45 of them would add about
#   300 MB to the app (Xcode bakes 1024 px renders of every appearance for phone and pad); flat,
#   about 16 MB.
#
# Editions the release script holds back (PENDING) or never ships (EXCLUDED) are left out, read from
# scripts/release/celebration-assets.sh so the two never disagree.
set -euo pipefail

root=$(cd "$(dirname "$0")/../.." && pwd)
art="$root/design/app-icon"
out="$root/Companion/AppIcons"
stamp="$out/.complete"
THEMES=(cobalt fern ember prism arcade)
# Points and scales of the iPhone app icon sizes.
SIZES=("20 2" "20 3" "29 2" "29 3" "40 2" "40 3" "60 2" "60 3")

fail() {
    echo "error: $*" >&2
    exit 1
}

eval "$(grep -E '^(PENDING|EXCLUDED)=' "$root/scripts/release/celebration-assets.sh")"

# Up to date when nothing in the artwork, the edition lists or this script changed since the last run.
if [ "${1:-}" != --force ] && [ -f "$stamp" ] && [ -z "$(find "$art/channel-themes" "$art/celebrations" \
    "$root/scripts/release/celebration-assets.sh" "$0" -newer "$stamp" -print -quit)" ]; then
    exit 0
fi

developer=${DEVELOPER_DIR:-$(xcode-select -p)}
ictool="$developer/../Applications/Icon Composer.app/Contents/Executables/ictool"
[ -x "$ictool" ] || fail "Icon Composer's ictool isn't at $ictool; the companion's icons need Xcode 26 or later."

# A document whose images are still Git LFS pointers would compile into a blank icon.
check_document() {
    local document=$1
    [ -f "$document/icon.json" ] || fail "${document#"$root/"} is missing; the icon artwork isn't checked out."
    for image in "$document"/Assets/*; do
        [ -f "$image" ] || continue
        if head -c 64 "$image" | grep -q "git-lfs.github.com/spec"; then
            fail "${image#"$root/"} is a Git LFS pointer. Run \`git lfs install && git lfs pull\`, then build again."
        fi
    done
}

flat_icon() {
    local name=$1 document=$2
    check_document "$document"
    local set="$out/CelebrationIcons.xcassets/AppIcon-$name.appiconset" images=()
    mkdir -p "$set"
    for appearance in light dark; do
        local rendition=Default luminosity=""
        if [ "$appearance" = dark ]; then
            rendition=Dark
            luminosity=', "appearances" : [ { "appearance" : "luminosity", "value" : "dark" } ]'
        fi
        local master="$set/$appearance-master.png"
        "$ictool" "$document" --export-image --output-file "$master" --platform iOS --rendition "$rendition" \
            --width 60 --height 60 --scale 3 >/dev/null || fail "ictool couldn't render ${document#"$root/"}."
        [ -s "$master" ] || fail "ictool rendered nothing for ${document#"$root/"}."
        for size in "${SIZES[@]}"; do
            read -r points scale <<<"$size"
            local file="$appearance-$points@${scale}x.png"
            sips -Z $((points * scale)) "$master" --out "$set/$file" >/dev/null
            images+=("{ \"filename\" : \"$file\", \"idiom\" : \"universal\", \"platform\" : \"ios\", \"scale\" : \"${scale}x\", \"size\" : \"${points}x$points\"$luminosity }")
        done
        rm "$master"
    done
    local joined
    joined=$(printf '%s,\n    ' "${images[@]}")
    printf '{\n  "images" : [\n    %s\n  ],\n  "info" : { "author" : "xcode", "version" : 1 }\n}\n' \
        "${joined%,*}" >"$set/Contents.json"
}

rm -rf "$out"
mkdir -p "$out/CelebrationIcons.xcassets"
printf '{\n  "info" : { "author" : "xcode", "version" : 1 }\n}\n' >"$out/CelebrationIcons.xcassets/Contents.json"

for theme in "${THEMES[@]}"; do
    document="$art/channel-themes/$theme/stable.icon"
    check_document "$document"
    cp -R "$document" "$out/AppIcon-$theme.icon"
done

flat_icon halloween "$art/channel-themes/halloween/stable.icon"
count=1
for dir in "$art"/celebrations/*/; do
    slug=$(basename "$dir")
    [[ " ${PENDING[*]} ${EXCLUDED[*]} " == *" $slug "* ]] && continue
    if [ ! -d "$dir/stable.icon" ]; then
        echo "warning: no Regular icon for $slug yet; the phone leaves it out" >&2
        continue
    fi
    flat_icon "$slug" "${dir%/}/stable.icon"
    count=$((count + 1))
done

touch "$stamp"
echo "app icons: ${#THEMES[@]} themes, $count celebrations in ${out#"$root/"}"
