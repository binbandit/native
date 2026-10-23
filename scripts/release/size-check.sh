#!/usr/bin/env bash
# Reports what Native costs to download and to install, and fails when either is over its budget, so
# size can't creep back unnoticed. The budgets and where the bytes go are in docs/app-size.md. It
# also fails when the app has no terminal (libghostty) or no script runtime: Xcode's build phases
# only warn when they can't build them, and such an app would look small and ship broken.
#
#   scripts/release/size-check.sh <app> [--zip <file>] [--dmg <file>]   # one app, e.g. a release's
#   scripts/release/size-check.sh --built <derived data> <configuration>...   # what check.sh built
#
# Without --zip it compresses the app the way release.sh packs Sparkle's update archive, so the
# download is measured from a plain build too.
set -euo pipefail
source "$(dirname "$0")/lib.sh"

# Budgets in MB (10^6 bytes, as Finder counts). Raise one only with a reason in docs/app-size.md.
BUDGET_DOWNLOAD=47
BUDGET_DMG=48
BUDGET_INSTALLED=118
BUDGET_BINARY=58.7
BUDGET_SCRIPT_RUNTIME=42

apps=() zip="" dmg="" derived=""
while [ $# -gt 0 ]; do
    case $1 in
        --zip) zip=$2; shift ;;
        --dmg) dmg=$2; shift ;;
        --built) derived=$2; shift ;;
        -h | --help) sed -n '2,11p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
        *) apps+=("${1%/}") ;;
    esac
    shift
done
if [ -n "$derived" ]; then
    configurations=(${apps[@]+"${apps[@]}"})
    apps=()
    for configuration in ${configurations[@]+"${configurations[@]}"}; do
        # Nightly names its app in its own xcconfig; the others take Shared's name.
        product=$(xcconfig_value NATIVE_PRODUCT_NAME "$configuration.xcconfig" 2>/dev/null || true)
        [ -n "$product" ] || product=$(xcconfig_value NATIVE_PRODUCT_NAME Shared.xcconfig)
        apps+=("$derived/Build/Products/$configuration/$product.app")
    done
fi
[ ${#apps[@]} -gt 0 ] || die "no app given (see --help)"
[ ${#apps[@]} = 1 ] || [ -z "$zip$dmg" ] || die "--zip and --dmg go with one app"

# The bytes in a file or folder, not the blocks they take on disk.
bytes() {
    find "$1" -type f -exec stat -f %z {} + | awk '{ total += $1 } END { print total + 0 }'
}

scratch=$(mktemp -d "${TMPDIR:-/tmp}/native-size.XXXXXX")
trap 'rm -rf "$scratch"' EXIT
over=0 incomplete=0

# Prints one row; with a budget, says how it compares and remembers when it's over.
row() {
    local label=$1 size=$2 budget=${3:-} mb
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

check() {
    local app=$1 name executable archive=$zip runtime host
    [ -d "$app/Contents" ] || die "not an app bundle: $app"
    name=$(basename "$app" .app)
    executable=$(plutil -extract CFBundleExecutable raw "$app/Contents/Info.plist")
    if [ -z "$archive" ]; then
        archive="$scratch/$name.zip"
        ditto -c -k --sequesterRsrc --keepParent "$app" "$archive"
    fi
    log "Size of $name"
    row "Download (update archive)" "$(bytes "$archive")" "$BUDGET_DOWNLOAD"
    [ -z "$dmg" ] || row "Download (disk image)" "$(bytes "$dmg")" "$BUDGET_DMG"
    row "Installed" "$(bytes "$app")" "$BUDGET_INSTALLED"
    row "  App binary" "$(bytes "$app/Contents/MacOS/$executable")" "$BUDGET_BINARY"
    runtime="$app/Contents/Helpers/native-script-runtime"
    if [ -x "$runtime" ]; then
        row "  Script runtime (V8)" "$(bytes "$runtime")" "$BUDGET_SCRIPT_RUNTIME"
    else
        printf '  %-30s %10s\n' "  Script runtime (V8)" "missing"
        warn "$name has no script runtime (scripts/build-script-runtime.sh needs Rust)"
        incomplete=1
    fi
    host=$(find "$app/Contents/Library/LoginItems" -maxdepth 1 -name '*.app' 2>/dev/null | head -1)
    [ -z "$host" ] || row "  Host helper" "$(bytes "$host")"
    row "  Frameworks" "$(bytes "$app/Contents/Frameworks")"
    row "  Resources" "$(bytes "$app/Contents/Resources")"
    if [ -f "$app/Contents/Resources/Assets.car" ]; then
        row "    Assets.car" "$(bytes "$app/Contents/Resources/Assets.car")"
    fi
    # The terminal is libghostty linked into the binary (its log line below comes from Ghostty's Zig
    # core, which nothing else in the app has) plus Ghostty's terminfo and shell integration.
    if ! LC_ALL=C grep -aqF "ghostty version=" "$app/Contents/MacOS/$executable" ||
        [ ! -f "$app/Contents/Resources/terminfo/78/xterm-ghostty" ] ||
        [ ! -d "$app/Contents/Resources/ghostty/shell-integration" ]; then
        warn "$name has no terminal: libghostty or Ghostty's resources are missing (scripts/build-libghostty.sh)"
        incomplete=1
    fi
}

for app in "${apps[@]}"; do check "$app"; done
[ "$incomplete" = 0 ] || die "a build that ships needs the terminal and the script runtime; build them first (docs/releasing.md, \"CI\")."
[ "$over" = 0 ] || die "over the size budget. docs/app-size.md says where the bytes go and how to find what grew."
