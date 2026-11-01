#!/bin/bash
# Exercises app-owned delegation through the production model with a local ACP fixture.
set -euo pipefail
instance=${1:?usage: delegation-admission.sh instance [scenario]}
root=$(git -C "$(dirname "$0")" rev-parse --show-toplevel)
derived="/tmp/native-dd/$instance"
products="$derived/Build/Products/Debug"
app="$products/Native.app"
work=$(mktemp -d -t native-delegation-admission)
trap 'rm -rf "$work"' EXIT
flags=(-I "$HOME/Library/Caches/native-build/libghostty/include" -parse-as-library -swift-version 6 -I "$products" -F "$products" -F "$products/PackageFrameworks")
for map in "$derived"/Build/Intermediates.noindex/GeneratedModuleMaps*/*.modulemap; do
    [ ! -e "$map" ] || flags+=(-Xcc "-fmodule-map-file=$map")
done
nice -n 10 xcrun swiftc "${flags[@]}" "$root/scripts/tests/delegation-admission.swift" \
    "$app/Contents/MacOS/Native.debug.dylib" \
    -Xlinker -rpath -Xlinker "$app/Contents/Frameworks" \
    -Xlinker -rpath -Xlinker "$app/Contents/MacOS" -o "$work/delegation-admission"
if [ $# -gt 1 ]; then
    "$work/delegation-admission" "$root/scripts/tests/delegation-agent.py" "$2"
else
    for scenario in cleanup resumed stop; do
        "$work/delegation-admission" "$root/scripts/tests/delegation-agent.py" "$scenario"
    done
fi
