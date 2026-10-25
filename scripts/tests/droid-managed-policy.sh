#!/bin/bash
# Runs the managed remote-host policy checks against one isolated Debug build, without launching its
# UI. `--before` runs only what compiles without the fix, to show the failure on a build without it.
# The organization's policy is simulated in memory or with launch arguments; nothing is written to
# managed preferences, and loopback-only keeps the app's own network code off this network.
set -euo pipefail
instance=${1:?usage: droid-managed-policy.sh instance [--before]}
root=$(git -C "$(dirname "$0")" rev-parse --show-toplevel)
derived="/tmp/native-dd/$instance"
products="$derived/Build/Products/Debug"
app="$products/Native.app"
work=$(mktemp -d -t native-droid-managed-policy)
trap 'rm -rf "$work"' EXIT
flags=(-I "$HOME/Library/Caches/native-build/libghostty/include" -parse-as-library -swift-version 6 -I "$products" -F "$products" -F "$products/PackageFrameworks")
for map in "$derived"/Build/Intermediates.noindex/GeneratedModuleMaps*/*.modulemap; do
    [ ! -e "$map" ] || flags+=(-Xcc "-fmodule-map-file=$map")
done
before=0
if [ "${2:-}" = --before ]; then flags+=(-D BEFORE); before=1; fi
nice -n 10 xcrun swiftc "${flags[@]}" "$root/scripts/tests/droid-managed-policy.swift" \
    "$app/Contents/MacOS/Native.debug.dylib" \
    -Xlinker -rpath -Xlinker "$app/Contents/Frameworks" \
    -Xlinker -rpath -Xlinker "$app/Contents/MacOS" -o "$work/droid-managed-policy"
check=("$work/droid-managed-policy" -check)
managed_off=(-policy.debug.managedKeys '(policy.remoteHosts.enabled)' -policy.remoteHosts.enabled '<false/>')
status=0
"${check[@]}" repro -NativeRemoteHosts YES -NativeRemoteHostsLoopbackOnly YES "${managed_off[@]}" || status=1
"${check[@]}" repro -NativeRemoteHosts YES -NativeRemoteHostsLoopbackOnly YES || status=1
"${check[@]}" repro -NativeRemoteHosts NO -NativeRemoteHostsLoopbackOnly YES || status=1
[ "$before" = 1 ] || "${check[@]}" matrix -NativeRemoteHosts YES || status=1
exit "$status"
