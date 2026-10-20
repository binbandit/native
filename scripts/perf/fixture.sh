#!/bin/bash
# Seeds an isolated instance with a workspace like a real one, for measuring launch: four projects,
# three with icons of their own (an SVG favicon, an SVG logo, an app icon in an asset catalog), and
# tasks listed for them (30 unless counts per project are given).
#
#   scripts/perf/fixture.sh <bundle id> <folder> [tasks in web api ios tools]
#
# The projects are made in <folder> once. The tasks go into the instance's saved session list, so
# write them again before every launch: Codex lists none for these folders, and its listing
# replaces them once it starts.
set -euo pipefail

[ $# -ge 2 ] || { echo "usage: $0 <bundle id> <folder> [tasks per project…]" >&2; exit 2; }
bundle=$1
root=$2
shift 2
[[ $bundle == *.dev.* ]] || { echo "$bundle isn't an isolated instance's bundle id" >&2; exit 1; }
names=(web api ios tools)
counts=(10 8 7 5)
[ $# -eq 0 ] || counts=("$@")

if [ ! -d "$root/tools/.git" ]; then
    mkdir -p "$root"/{web/public,api/assets,ios/App/Assets.xcassets/AppIcon.appiconset,tools}
    cat >"$root/web/public/favicon.svg" <<'SVG'
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 64 64"><defs><linearGradient id="g" x1="0" y1="0" x2="1" y2="1"><stop offset="0" stop-color="#5b8cff"/><stop offset="1" stop-color="#9b5bff"/></linearGradient></defs><rect width="64" height="64" rx="14" fill="url(#g)"/><path d="M16 44 L32 14 L48 44 Z" fill="#fff" opacity=".9"/><circle cx="32" cy="36" r="6" fill="#5b8cff"/></svg>
SVG
    cat >"$root/api/assets/logo.svg" <<'SVG'
<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 48 48"><circle cx="24" cy="24" r="22" fill="#1f9d74"/><path d="M14 25c4 6 16 6 20 0M16 18h4M28 18h4" stroke="#fff" stroke-width="3" fill="none" stroke-linecap="round"/></svg>
SVG
    sips -s format png -z 1024 1024 \
        /System/Library/CoreServices/CoreTypes.bundle/Contents/Resources/GenericApplicationIcon.icns \
        --out "$root/ios/App/Assets.xcassets/AppIcon.appiconset/icon-1024.png" >/dev/null
    printf '{"images":[{"filename":"icon-1024.png","idiom":"universal","platform":"ios","size":"1024x1024"}],"info":{"author":"xcode","version":1}}\n' \
        >"$root/ios/App/Assets.xcassets/AppIcon.appiconset/Contents.json"
    for project in "${names[@]}"; do
        printf '# %s\n' "$project" >"$root/$project/README.md"
        git -C "$root/$project" init -q -b main
        git -C "$root/$project" add -A
        git -C "$root/$project" -c user.name=perf -c user.email=perf@example.com commit -qm "First commit"
    done
fi

projects=""
catalog=""
n=0
now=$(date +%s)
for i in "${!names[@]}"; do
    id=$(printf '00000000-0000-4000-8000-%012d' $((i + 1)))
    projects+="${projects:+,}{\"id\":\"$id\",\"url\":\"file://$root/${names[$i]}/\",\"host\":\"local\"}"
    sessions=""
    for ((j = 1; j <= ${counts[$i]:-0}; j++)); do
        n=$((n + 1))
        updated=$(date -u -r $((now - n * 3600)) +%Y-%m-%dT%H:%M:%S.000Z)
        sessions+="${sessions:+,}{\"sessionId\":\"$(printf '00000000-0000-4000-9000-%012d' "$n")\",\"cwd\":\"$root/${names[$i]}\",\"title\":\"Task $n in ${names[$i]}: tidy the module and update its tests\",\"updatedAt\":\"$updated\"}"
    done
    catalog+="${catalog:+,}\"$id\",[{\"rawValue\":\"codex\"},[$sessions]]"
done
defaults write "$bundle" projects -data "$(printf '[%s]' "$projects" | xxd -p | tr -d '\n')"
defaults write "$bundle" defaultAgent codex
# The sidebar at its default width every time (`just perf --fixture` also ignores the saved window).
defaults delete "$bundle" "NSSplitView Subview Frames main, SidebarNavigationSplitView" 2>/dev/null || true
mkdir -p "$HOME/Library/Application Support/$bundle"
printf '[%s]' "$catalog" >"$HOME/Library/Application Support/$bundle/session-catalog.json"
