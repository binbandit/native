#!/bin/bash
# Exercises sidebar folding from the isolated Debug build with inert sessions, without opening windows.
set -euo pipefail
instance=${1:?usage: sidebar-folding.sh instance}
root=$(git -C "$(dirname "$0")" rev-parse --show-toplevel)
derived="/tmp/native-dd/$instance"
products="$derived/Build/Products/Debug"
app="$products/Native.app"
work=$(mktemp -d -t native-sidebar-folding)
trap 'rm -rf "$work"' EXIT
flags=(-I "$HOME/Library/Caches/native-build/libghostty/include" -parse-as-library -swift-version 6 -I "$products" -F "$products" -F "$products/PackageFrameworks")
for map in "$derived"/Build/Intermediates.noindex/GeneratedModuleMaps*/*.modulemap; do
    [ ! -e "$map" ] || flags+=(-Xcc "-fmodule-map-file=$map")
done
nice -n 10 xcrun swiftc "${flags[@]}" "$root/scripts/tests/sidebar-folding.swift" \
    "$app/Contents/MacOS/Native.debug.dylib" \
    -Xlinker -rpath -Xlinker "$app/Contents/Frameworks" \
    -Xlinker -rpath -Xlinker "$app/Contents/MacOS" -o "$work/sidebar-folding"
mkdir "$work/plugins"
"$work/sidebar-folding" -pluginsDirectory "$work/plugins"
