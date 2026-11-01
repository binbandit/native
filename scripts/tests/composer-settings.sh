#!/bin/bash
# Runs focused settings regressions against an isolated Debug build, without launching a window.
set -euo pipefail
instance=${1:?usage: composer-settings.sh instance [--geometry]}
shift
if [[ " ${*:-} " == *" --geometry "* ]] && [[ $(/tmp/native-tools/screenlocked) == locked ]]; then
    echo "SKIP: screen locked; no geometry measurement or capture attempted"
    exit 2
fi
root=$(git -C "$(dirname "$0")" rev-parse --show-toplevel)
derived="/tmp/native-dd/$instance"
products="$derived/Build/Products/Debug"
app="$products/Native.app"
work=$(mktemp -d -t native-composer-settings)
trap 'rm -rf "$work"' EXIT
flags=(-I "$HOME/Library/Caches/native-build/libghostty/include" -parse-as-library -swift-version 6 -I "$products" -F "$products" -F "$products/PackageFrameworks")
for map in "$derived"/Build/Intermediates.noindex/GeneratedModuleMaps*/*.modulemap; do
    [ ! -e "$map" ] || flags+=(-Xcc "-fmodule-map-file=$map")
done
nice -n 10 xcrun swiftc "${flags[@]}" "$root/scripts/tests/composer-settings.swift" \
    "$root/Packages/ACP/Tests/ACPTests/GatewayWire.swift" \
    "$app/Contents/MacOS/Native.debug.dylib" \
    -Xlinker -rpath -Xlinker "$app/Contents/Frameworks" \
    -Xlinker -rpath -Xlinker "$app/Contents/MacOS" -o "$work/composer-settings"
nice -n 10 "$work/composer-settings" "$@"
