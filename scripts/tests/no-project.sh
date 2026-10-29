#!/bin/bash
# Swift Testing against the isolated Debug app module, with an in-memory host and private temp files.
set -euo pipefail
instance=${1:?usage: no-project.sh instance}
root=$(git -C "$(dirname "$0")" rev-parse --show-toplevel)
derived="/tmp/native-dd/$instance"
products="$derived/Build/Products/Debug"
app="$products/Native.app"
work=$(mktemp -d -t native-no-project)
trap 'rm -rf "$work"' EXIT
testing="$(xcrun --show-sdk-platform-path)/Developer/Library/Frameworks"
toolchain=$(dirname "$(dirname "$(xcrun --find swiftc)")")
flags=(-I "$HOME/Library/Caches/native-build/libghostty/include" -parse-as-library -swift-version 6 -I "$products" -F "$products" -F "$products/PackageFrameworks" -F "$testing" -framework Testing -load-plugin-library "$toolchain/lib/swift/host/plugins/testing/libTestingMacros.dylib")
for map in "$derived"/Build/Intermediates.noindex/GeneratedModuleMaps*/*.modulemap; do
    [ ! -e "$map" ] || flags+=(-Xcc "-fmodule-map-file=$map")
done
nice -n 10 xcrun swiftc "${flags[@]}" "$root/scripts/tests/no-project.swift" "$root/scripts/tests/no-project-host.swift" \
    "$app/Contents/MacOS/Native.debug.dylib" \
    -Xlinker -rpath -Xlinker "$testing" \
    -Xlinker -rpath -Xlinker "$app/Contents/Frameworks" \
    -Xlinker -rpath -Xlinker "$app/Contents/MacOS" -o "$work/no-project"
mkdir "$work/plugins"
nice -n 10 "$work/no-project" -pluginsDirectory "$work/plugins"
