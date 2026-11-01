#!/bin/bash
# Exercises the real composer in an offscreen host, without launching Native or posting key events.
set -euo pipefail
instance=${1:?usage: composer-field-input.sh instance}
root=$(git -C "$(dirname "$0")" rev-parse --show-toplevel)
derived="/tmp/native-dd/$instance"
products="$derived/Build/Products/Debug"
app="$products/Native.app"
work=$(mktemp -d -t native-composer-field-input)
trap 'rm -rf "$work"' EXIT
mkdir -p "$work/project/fixtures"
git -C "$work/project" init --quiet
printf 'Fixture attachment\n' >"$work/project/fixtures/guide.txt"
flags=(-I "$HOME/Library/Caches/native-build/libghostty/include" -parse-as-library -swift-version 6 -default-isolation MainActor -I "$products" -F "$products" -F "$products/PackageFrameworks")
for map in "$derived"/Build/Intermediates.noindex/GeneratedModuleMaps*/*.modulemap; do
    [ ! -e "$map" ] || flags+=(-Xcc "-fmodule-map-file=$map")
done
nice -n 10 xcrun swiftc "${flags[@]}" "$root/scripts/tests/composer-field-input.swift" \
    "$app/Contents/MacOS/Native.debug.dylib" \
    -Xlinker -rpath -Xlinker "$app/Contents/Frameworks" \
    -Xlinker -rpath -Xlinker "$app/Contents/MacOS" -o "$work/composer-field-input"
nice -n 10 "$work/composer-field-input" "$work/project" -sounds.enabled NO -native.mute YES
