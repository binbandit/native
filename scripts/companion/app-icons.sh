#!/bin/bash
# Links the iPhone app's alternate icons to the Regular icon documents the icon work already made
# (docs/companion.md, "App icons"): every theme in design/app-icon/channel-themes and every
# celebration edition (each style) in design/app-icon/celebrations. Nothing is copied or drawn here:
# Companion/NativeCompanion/AppIcons/AppIcon-<name>.icon are symlinks, and Xcode compiles each one
# into the light, dark, tinted and clear icons the document describes.
#
#   scripts/companion/app-icons.sh     # re-run when an edition is added or removed; commit the links
#
# Editions the release script holds back (PENDING) or never ships (EXCLUDED) are left out, read from
# scripts/release/celebration-assets.sh so the two never disagree.
set -euo pipefail

root=$(git -C "$(dirname "$0")" rev-parse --show-toplevel)
art="$root/design/app-icon"
out="$root/Companion/NativeCompanion/AppIcons"
eval "$(grep -E '^(PENDING|EXCLUDED)=' "$root/scripts/release/celebration-assets.sh")"
THEMES=(cobalt fern ember prism arcade halloween)

rm -rf "$out"
mkdir -p "$out"

link() {
    local name=$1 document=$2
    [ -f "$document/icon.json" ] || { echo "skipping $name: no $document" >&2; return; }
    ln -s "../../../${document#"$root/"}" "$out/AppIcon-$name.icon"
}

for theme in "${THEMES[@]}"; do
    link "$theme" "$art/channel-themes/$theme/stable.icon"
done
for dir in "$art"/celebrations/*/; do
    dir=${dir%/}
    slug=$(basename "$dir")
    [[ " ${PENDING[*]} ${EXCLUDED[*]} " == *" $slug "* ]] && continue
    link "$slug" "$dir/stable.icon"
done

ls "$out" | wc -l | xargs echo "icons linked:"
