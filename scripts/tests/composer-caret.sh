#!/bin/bash
# Types into the real composer editor from an isolated Debug build, without launching the app.
set -euo pipefail
instance=${1:?usage: composer-caret.sh instance [--render folder]}
shift
root=$(git -C "$(dirname "$0")" rev-parse --show-toplevel)
derived="/tmp/native-dd/$instance"
products="$derived/Build/Products/Debug"
app="$products/Native.app"
work=$(mktemp -d -t native-composer-caret)
trap 'rm -rf "$work"' EXIT
flags=(-I "$HOME/Library/Caches/native-build/libghostty/include" -parse-as-library -swift-version 6 -I "$products" -F "$products" -F "$products/PackageFrameworks")
for map in "$derived"/Build/Intermediates.noindex/GeneratedModuleMaps*/*.modulemap; do
    [ ! -e "$map" ] || flags+=(-Xcc "-fmodule-map-file=$map")
done
# A bundle around the check, so `Bundle.main` has the app's fonts and the editor draws in Geist, and
# any standard-default writes belong to this isolated instance, never the installed application.
bundle="$work/ComposerCaret.app"
mkdir -p "$bundle/Contents/MacOS" "$bundle/Contents/Resources"
cp "$app"/Contents/Resources/Geist*.ttf "$bundle/Contents/Resources/"
plutil -create xml1 "$bundle/Contents/Info.plist"
plutil -insert CFBundleIdentifier -string "dev.binbandit.native.dev.$instance" "$bundle/Contents/Info.plist"
plutil -insert CFBundleExecutable -string composer-caret "$bundle/Contents/Info.plist"
executable="$bundle/Contents/MacOS/composer-caret"
nice -n 10 xcrun swiftc "${flags[@]}" "$root/scripts/tests/composer-caret.swift" \
    "$app/Contents/MacOS/Native.debug.dylib" \
    -Xlinker -rpath -Xlinker "$app/Contents/Frameworks" \
    -Xlinker -rpath -Xlinker "$app/Contents/MacOS" -o "$executable"
"$executable" "$@"
