#!/usr/bin/env bash
# Reports what Native costs to download and to install, and fails when either is over its budget, so
# size can't creep back unnoticed. The budgets and where the bytes go are in docs/app-size.md.
# check.sh runs it on every Release build it makes; release.sh on the archives it publishes.
#
#   scripts/release/size.sh <app> [--zip <file>] [--dmg <file>]
#
# Without --zip it compresses the app the way release.sh packs Sparkle's update archive, so the
# download is measured from a plain build too.
set -euo pipefail
source "$(dirname "$0")/lib.sh"

# Budgets in MB (10^6 bytes, as Finder counts). Raise one only with a reason in docs/app-size.md.
BUDGET_DOWNLOAD=45
BUDGET_DMG=46
BUDGET_INSTALLED=125
BUDGET_BINARY=66
BUDGET_SCRIPT_RUNTIME=42

app="" zip="" dmg=""
while [ $# -gt 0 ]; do
    case $1 in
        --zip) zip=$2; shift ;;
        --dmg) dmg=$2; shift ;;
        -h | --help) sed -n '2,9p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
        *) [ -z "$app" ] || die "one app at a time (see --help)"; app=${1%/} ;;
    esac
    shift
done
[ -d "$app/Contents" ] || die "not an app bundle: ${app:-nothing given} (see --help)"

# The bytes in a file or folder, not the blocks they take on disk.
bytes() {
    find "$1" -type f -exec stat -f %z {} + | awk '{ total += $1 } END { print total + 0 }'
}

if [ -z "$zip" ]; then
    scratch=$(mktemp -d "${TMPDIR:-/tmp}/native-size.XXXXXX")
    trap 'rm -rf "$scratch"' EXIT
    zip="$scratch/$(basename "$app" .app).zip"
    ditto -c -k --sequesterRsrc --keepParent "$app" "$zip"
fi

name=$(basename "$app" .app)
executable=$(plutil -extract CFBundleExecutable raw "$app/Contents/Info.plist")
over=0
# Prints one row; with a budget, marks it and remembers when it's over.
row() {
    local label=$1 size=$2 budget=${3:-}
    local mb
    mb=$(awk -v b="$size" 'BEGIN { printf "%.1f", b / 1e6 }')
    if [ -z "$budget" ]; then
        printf '  %-30s %7s MB\n' "$label" "$mb"
    elif awk -v b="$size" -v max="$budget" 'BEGIN { exit !(b > max * 1e6) }'; then
        printf '  %-30s %7s MB  over its %s MB budget\n' "$label" "$mb" "$budget"
        over=1
    else
        printf '  %-30s %7s MB  of %s MB\n' "$label" "$mb" "$budget"
    fi
}

log "Size of $name"
row "Download (update archive)" "$(bytes "$zip")" "$BUDGET_DOWNLOAD"
[ -z "$dmg" ] || row "Download (disk image)" "$(bytes "$dmg")" "$BUDGET_DMG"
row "Installed" "$(bytes "$app")" "$BUDGET_INSTALLED"
row "  App binary" "$(bytes "$app/Contents/MacOS/$executable")" "$BUDGET_BINARY"
runtime="$app/Contents/Helpers/native-script-runtime"
if [ -f "$runtime" ]; then
    row "  Script runtime (V8)" "$(bytes "$runtime")" "$BUDGET_SCRIPT_RUNTIME"
else
    printf '  %-30s %10s\n' "  Script runtime (V8)" "not built"
fi
host=$(find "$app/Contents/Library/LoginItems" -maxdepth 1 -name '*.app' 2>/dev/null | head -1)
[ -z "$host" ] || row "  Host helper" "$(bytes "$host")"
row "  Frameworks" "$(bytes "$app/Contents/Frameworks")"
row "  Resources" "$(bytes "$app/Contents/Resources")"
[ -f "$app/Contents/Resources/Assets.car" ] && row "    Assets.car" "$(bytes "$app/Contents/Resources/Assets.car")"
# Builds without Zig have no terminal (scripts/build-libghostty.sh), so they come in about 11 MB
# under what ships; say so rather than let the numbers look better than they are.
[ -d "$app/Contents/Resources/terminfo" ] || warn "this build has no terminal (libghostty); a release is about 11 MB bigger"

if [ "$over" = 1 ]; then
    die "$name is over its size budget. docs/app-size.md says where the bytes go and how to find what grew."
fi
