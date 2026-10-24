#!/bin/bash
# Runs the app-model regression checks against one isolated Debug build, without launching its UI.
set -euo pipefail
instance=${1:?usage: droid-task-routing.sh instance [--before]}
root=$(git -C "$(dirname "$0")" rev-parse --show-toplevel)
derived="/tmp/native-dd/$instance"
products="$derived/Build/Products/Debug"
app="$products/Native.app"
work=$(mktemp -d -t native-droid-task-routing)
trap 'rm -rf "$work"' EXIT
flags=(-I "$HOME/Library/Caches/native-build/libghostty/include" -parse-as-library -swift-version 6 -I "$products" -F "$products" -F "$products/PackageFrameworks")
for map in "$derived"/Build/Intermediates.noindex/GeneratedModuleMaps*/*.modulemap; do
    [ ! -e "$map" ] || flags+=(-Xcc "-fmodule-map-file=$map")
done
if [ "${2:-}" = --before ]; then flags+=(-D BEFORE); fi
nice -n 10 xcrun swiftc "${flags[@]}" "$root/scripts/tests/droid-task-routing.swift" \
    "$app/Contents/MacOS/Native.debug.dylib" \
    -Xlinker -rpath -Xlinker "$app/Contents/Frameworks" \
    -Xlinker -rpath -Xlinker "$app/Contents/MacOS" -o "$work/droid-task-routing"
"$work/droid-task-routing" -NativeRemoteHosts YES
