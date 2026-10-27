#!/bin/bash
# Dispatches mouse events through AppKit in an unshown SwiftUI toolbar window.
set -euo pipefail
root=$(git -C "$(dirname "$0")" rev-parse --show-toplevel)
work=$(mktemp -d -t native-titlebar-double-click)
trap 'rm -rf "$work"' EXIT
sources=("$root/scripts/tests/titlebar-double-click.swift")
flags=(-parse-as-library -swift-version 6)
if [ "${1:-}" = --before ]; then
    flags+=(-D BEFORE)
else
    sources+=("$root/native/Platform/PlatformTitlebarDoubleClick.swift")
fi
nice -n 10 xcrun swiftc "${flags[@]}" "${sources[@]}" -o "$work/titlebar-double-click"
"$work/titlebar-double-click"
