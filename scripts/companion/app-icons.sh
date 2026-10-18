#!/bin/bash
# Builds the iPhone app's alternate icons from the icon work's documents in design/app-icon
# (docs/companion.md, "App icons"). The companion target runs it before compiling anything; its
# output, Companion/AppIcons/, is a build product: gitignored, never committed. Nothing here draws
# or edits artwork.
#
#   scripts/companion/app-icons.sh [--force]
#
# - The five themes stay layered: their Regular stable.icon documents are copied as
#   AppIcon-<theme>.icon, and Xcode compiles light, dark, tinted and clear from each.
# - Every celebration edition and style is flat: Icon Composer's ictool renders its Regular
#   stable.icon in light and dark at the iPhone icon sizes, into
#   IconArtwork.xcassets/AppIcon-<edition>.appiconset. Layered, the 45 of them would add about
#   300 MB to the app (Xcode bakes 1024 px renders of every appearance for phone and pad); flat,
#   about 23 MB.
# - Every icon, the primary included, gets a small light and dark preview for the app's pickers
#   (IconArtwork.xcassets/IconPreview-<name>.imageset), since iOS can't load app icons as images.
#
# Editions the release script holds back (PENDING) or never ships (EXCLUDED) are left out, read from
# scripts/release/celebration-assets.sh so the two never disagree.
set -euo pipefail

root=$(cd "$(dirname "$0")/../.." && pwd)
art="$root/design/app-icon"
out="$root/Companion/AppIcons"
catalog="$out/IconArtwork.xcassets"
stamp="$out/.complete"
THEMES=(cobalt fern ember prism arcade)
# Points and scales of the iPhone app icon sizes.
SIZES=("20 2" "20 3" "29 2" "29 3" "40 2" "40 3" "60 2" "60 3")
# Previews show at up to 48 points.
PREVIEW=144

fail() {
    echo "error: $*" >&2
    exit 1
}

eval "$(grep -E '^(PENDING|EXCLUDED)=' "$root/scripts/release/celebration-assets.sh")"

# Up to date when nothing in the artwork, the edition lists or this script changed since the last run.
if [ "${1:-}" != --force ] && [ -f "$stamp" ] && [ -z "$(find "$art/channel-themes" "$art/celebrations" \
    "$root/native/AppIcon.icon" "$root/scripts/release/celebration-assets.sh" "$0" -newer "$stamp" -print -quit)" ]; then
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

# render <document> <Default|Dark> <points> <output>: the icon as iOS draws it, at 3x.
render() {
    "$ictool" "$1" --export-image --output-file "$4" --platform iOS --rendition "$2" --width "$3" --height "$3" \
        --scale 3 >/dev/null || fail "ictool couldn't render ${1#"$root/"}."
    [ -s "$4" ] || fail "ictool rendered nothing for ${1#"$root/"}."
}

json_set() {
    local joined
    joined=$(printf '%s,\n    ' "$@")
    printf '{\n  "images" : [\n    %s\n  ],\n  "info" : { "author" : "xcode", "version" : 1 }\n}\n' "${joined%,*}"
}

dark=', "appearances" : [ { "appearance" : "luminosity", "value" : "dark" } ]'

# preview <name> <light png> <dark png>: an imageset the pickers show, made from renders.
preview() {
    local set="$catalog/IconPreview-$1.imageset"
    mkdir -p "$set"
    sips -Z "$PREVIEW" "$2" --out "$set/light.png" >/dev/null
    sips -Z "$PREVIEW" "$3" --out "$set/dark.png" >/dev/null
    json_set "{ \"filename\" : \"light.png\", \"idiom\" : \"universal\" }" \
        "{ \"filename\" : \"dark.png\", \"idiom\" : \"universal\"$dark }" >"$set/Contents.json"
}

layered_icon() {
    local name=$1 document=$2 scratch
    check_document "$document"
    [ "$name" = original ] || cp -R "$document" "$out/AppIcon-$name.icon"
    scratch=$(mktemp -d)
    render "$document" Default 48 "$scratch/light.png"
    render "$document" Dark 48 "$scratch/dark.png"
    preview "$name" "$scratch/light.png" "$scratch/dark.png"
    rm -rf "$scratch"
}

flat_icon() {
    local name=$1 document=$2
    check_document "$document"
    local set="$catalog/AppIcon-$name.appiconset" images=()
    mkdir -p "$set"
    for appearance in light dark; do
        local rendition=Default luminosity=""
        [ "$appearance" = dark ] && rendition=Dark luminosity=$dark
        render "$document" "$rendition" 60 "$set/$appearance-master.png"
        for size in "${SIZES[@]}"; do
            read -r points scale <<<"$size"
            local file="$appearance-$points@${scale}x.png"
            sips -Z $((points * scale)) "$set/$appearance-master.png" --out "$set/$file" >/dev/null
            images+=("{ \"filename\" : \"$file\", \"idiom\" : \"universal\", \"platform\" : \"ios\", \"scale\" : \"${scale}x\", \"size\" : \"${points}x$points\"$luminosity }")
        done
    done
    json_set "${images[@]}" >"$set/Contents.json"
    preview "$name" "$set/light-master.png" "$set/dark-master.png"
    rm "$set"/*-master.png
}

rm -rf "$out"
mkdir -p "$catalog"
printf '{\n  "info" : { "author" : "xcode", "version" : 1 }\n}\n' >"$catalog/Contents.json"

layered_icon original "$root/native/AppIcon.icon"
for theme in "${THEMES[@]}"; do
    layered_icon "$theme" "$art/channel-themes/$theme/stable.icon"
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
