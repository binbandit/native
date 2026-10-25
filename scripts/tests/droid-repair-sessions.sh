#!/bin/bash
# Runs the re-pairing regression checks against one isolated Debug build, without launching its UI.
# `--before` leaves out what only compiles with the fix, to show the failure on a build without it.
set -euo pipefail
instance=${1:?usage: droid-repair-sessions.sh instance [--before]}
root=$(git -C "$(dirname "$0")" rev-parse --show-toplevel)
derived="/tmp/native-dd/$instance"
products="$derived/Build/Products/Debug"
app="$products/Native.app"
work=$(mktemp -d -t native-droid-repair-sessions)
trap 'rm -rf "$work"' EXIT
flags=(-I "$HOME/Library/Caches/native-build/libghostty/include" -parse-as-library -swift-version 6 -I "$products" -F "$products" -F "$products/PackageFrameworks")
for map in "$derived"/Build/Intermediates.noindex/GeneratedModuleMaps*/*.modulemap; do
    [ ! -e "$map" ] || flags+=(-Xcc "-fmodule-map-file=$map")
done
if [ "${2:-}" = --before ]; then flags+=(-D BEFORE); fi
nice -n 10 xcrun swiftc "${flags[@]}" "$root/scripts/tests/droid-repair-sessions.swift" \
    "$app/Contents/MacOS/Native.debug.dylib" \
    -Xlinker -rpath -Xlinker "$app/Contents/Frameworks" \
    -Xlinker -rpath -Xlinker "$app/Contents/MacOS" -o "$work/droid-repair-sessions"
"$work/droid-repair-sessions" -NativeRemoteHosts YES
