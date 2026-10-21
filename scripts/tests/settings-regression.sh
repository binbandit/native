#!/bin/bash
# Exercises Settings models from an isolated Debug build without launching the app.
set -euo pipefail
instance=${1:?usage: settings-regression.sh instance [--before]}
root=$(git -C "$(dirname "$0")" rev-parse --show-toplevel)
derived="/tmp/native-dd/$instance"
products="$derived/Build/Products/Debug"
app="$products/Native.app"
work=$(mktemp -d -t native-settings-regression)
trap 'rm -rf "$work"' EXIT
flags=(-I "$HOME/Library/Caches/native-build/libghostty/include" -parse-as-library -swift-version 6 -I "$products" -F "$products" -F "$products/PackageFrameworks")
for map in "$derived"/Build/Intermediates.noindex/GeneratedModuleMaps*/*.modulemap; do
    [ ! -e "$map" ] || flags+=(-Xcc "-fmodule-map-file=$map")
done
if [ "${2:-}" = --before ]; then flags+=(-D BEFORE); fi
nice -n 10 xcrun swiftc "${flags[@]}" "$root/scripts/tests/settings-regression.swift" \
    "$app/Contents/MacOS/Native.debug.dylib" \
    -Xlinker -rpath -Xlinker "$app/Contents/Frameworks" \
    -Xlinker -rpath -Xlinker "$app/Contents/MacOS" -o "$work/settings-regression"
mkdir "$work/plugins"
"$work/settings-regression" -pluginsDirectory "$work/plugins" -NativeRemoteHosts YES
