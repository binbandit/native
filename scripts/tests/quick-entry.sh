#!/bin/bash
# Checks the real task-start pipeline without launching the UI, agents, or a persistent host.
set -euo pipefail
instance=${1:?usage: quick-entry.sh instance}
root=$(git -C "$(dirname "$0")" rev-parse --show-toplevel)
derived="/tmp/native-dd/$instance"
products="$derived/Build/Products/Debug"
app="$products/Native.app"
work=$(mktemp -d -t native-quick-entry)
trap 'rm -rf "$work"' EXIT
flags=(-I "$HOME/Library/Caches/native-build/libghostty/include" -parse-as-library -swift-version 6 -I "$products" -F "$products" -F "$products/PackageFrameworks")
for map in "$derived"/Build/Intermediates.noindex/GeneratedModuleMaps*/*.modulemap; do
    [ ! -e "$map" ] || flags+=(-Xcc "-fmodule-map-file=$map")
done
# Any standard-default writes belong to this isolated instance, never the installed application.
executable="$work/dev.binbandit.native.dev.$instance"
nice -n 10 xcrun swiftc "${flags[@]}" "$root/scripts/tests/quick-entry.swift" "$root/scripts/tests/quick-entry-host.swift" \
    "$app/Contents/MacOS/Native.debug.dylib" \
    -Xlinker -rpath -Xlinker "$app/Contents/Frameworks" \
    -Xlinker -rpath -Xlinker "$app/Contents/MacOS" -o "$executable"
nice -n 10 "$executable" -pluginsDirectory "$work/plugins"
