#!/bin/bash
# Exercises task pull-request outcomes and lookups against one isolated Debug build.
set -euo pipefail
instance=${1:?usage: sidebar-pull-requests.sh instance}
root=$(git -C "$(dirname "$0")" rev-parse --show-toplevel)
derived="/tmp/native-dd/$instance"
products="$derived/Build/Products/Debug"
app="$products/Native.app"
work=$(mktemp -d -t native-sidebar-pull-requests)
trap 'rm -rf "$work"' EXIT
flags=(-I "$HOME/Library/Caches/native-build/libghostty/include" -parse-as-library -swift-version 6 -I "$products" -F "$products" -F "$products/PackageFrameworks")
for map in "$derived"/Build/Intermediates.noindex/GeneratedModuleMaps*/*.modulemap; do
    [ ! -e "$map" ] || flags+=(-Xcc "-fmodule-map-file=$map")
done
nice -n 10 xcrun swiftc "${flags[@]}" "$root/scripts/tests/sidebar-pull-requests.swift" \
    "$root/scripts/tests/sidebar-archived-pull-requests.swift" \
    "$app/Contents/MacOS/Native.debug.dylib" \
    -Xlinker -rpath -Xlinker "$app/Contents/Frameworks" \
    -Xlinker -rpath -Xlinker "$app/Contents/MacOS" -o "$work/sidebar-pull-requests"
nice -n 10 "$work/sidebar-pull-requests" -pluginsDirectory "$work/plugins"

# With the pull-requests fixture running, also verify the real row labels. The fixture's default
# preferences hide every optional fact, so these outcomes must remain independently visible.
if [ "${2-}" = --ui ]; then
    if [ "$(/tmp/native-tools/screenlocked)" = locked ]; then
        echo "UI check pending: screen locked" >&2
        exit 2
    fi
    "$root/scripts/dev/drive.sh" "$instance" tree --depth 20 >"$work/tree.txt"
    if [ ! -s "$work/tree.txt" ]; then
        echo "UI check pending: macOS exposes no accessibility window for the isolated instance" >&2
        exit 2
    fi
    for expected in 'pull request #101, open' 'pull request #102, draft' \
        'pull request #103, merged' 'pull request #104, closed' 'pull request #105, open, checks:' 'pull request #106, merged'; do
        if ! rg -F -q "$expected" "$work/tree.txt"; then
            echo "FAIL: real sidebar is missing $expected" >&2
            exit 1
        fi
    done
    for number in 101 102 103 104 105 106; do
        rg -F -q "#sidebar-pr-$number" "$work/tree.txt" || {
            echo "FAIL: real sidebar is missing badge $number" >&2
            exit 1
        }
    done
    echo 'PASS: real All in view rows expose every pull-request outcome with optional facts hidden'
fi
