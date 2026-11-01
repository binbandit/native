#!/bin/bash
# Exercises the real row adapter and session with local ACP pipes, without providers or app windows.
set -euo pipefail
instance=${1:?usage: composer-row-settings.sh instance}
root=$(git -C "$(dirname "$0")" rev-parse --show-toplevel)
derived="/tmp/native-dd/$instance"
products="$derived/Build/Products/Debug"
app="$products/Native.app"
work=$(mktemp -d -t native-composer-row-settings)
trap 'rm -rf "$work"' EXIT
flags=(-I "$HOME/Library/Caches/native-build/libghostty/include" -parse-as-library -swift-version 6 -default-isolation MainActor -I "$products" -F "$products" -F "$products/PackageFrameworks")
for map in "$derived"/Build/Intermediates.noindex/GeneratedModuleMaps*/*.modulemap; do
    [ ! -e "$map" ] || flags+=(-Xcc "-fmodule-map-file=$map")
done
nice -n 10 xcrun swiftc "${flags[@]}" "$root/scripts/tests/composer-row-settings.swift" \
    "$root/Packages/ACP/Tests/ACPTests/GatewayWire.swift" "$app/Contents/MacOS/Native.debug.dylib" \
    -Xlinker -rpath -Xlinker "$app/Contents/Frameworks" \
    -Xlinker -rpath -Xlinker "$app/Contents/MacOS" -o "$work/composer-row-settings"
nice -n 10 "$work/composer-row-settings" -sounds.enabled NO -native.mute YES
