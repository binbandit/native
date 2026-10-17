#!/bin/bash
# Type-checks app folders for iPadOS, until the app has an iPadOS destination.
#
#   scripts/check-ios.sh native/DesignSystem native/Views/Sidebar
#
# Run from anywhere in the repo. Compiles the given folders together with native/DesignSystem
# (every feature uses it) against the iOS simulator SDK in Swift 6 mode with the app's settings
# (MainActor by default, member import visibility). `#Preview` blocks are stripped, since the
# preview macro isn't available outside Xcode. Swift packages the files import (ACP, Git, …) are
# built for iOS first from Packages/*/Sources. Code that uses other app folders needs those folders
# listed too. Prints the errors and warnings, and exits non-zero if there are errors.
set -euo pipefail

if [ $# -eq 0 ]; then
    echo "usage: scripts/check-ios.sh <folder or file>…" >&2
    exit 2
fi

root=$(git -C "$(dirname "$0")" rev-parse --show-toplevel)
cd "$root"
work=$(mktemp -d -t native-check-ios)
trap 'rm -rf "$work"' EXIT
mkdir -p "$work/sources" "$work/modules"

sdk=$(xcrun --sdk iphonesimulator --show-sdk-path)
target="arm64-apple-ios27.0-simulator"
flags=(-swift-version 6 -enable-upcoming-feature MemberImportVisibility -target "$target" -sdk "$sdk" -I "$work/modules")

# Copies Swift files into $2 with #Preview blocks removed.
strip_previews() {
    python3 - "$1" "$2" <<'PY'
import os, sys
src, dest = sys.argv[1], sys.argv[2]
paths = [src] if os.path.isfile(src) else [os.path.join(d, f) for d, _, fs in os.walk(src) for f in fs]
for path in paths:
    if not path.endswith(".swift"):
        continue
    text = open(path).read()
    out, i = [], 0
    while (j := text.find("#Preview", i)) >= 0:
        out.append(text[i:j])
        k, depth = text.find("{", j), 0
        while True:
            depth += {"{": 1, "}": -1}.get(text[k], 0)
            if depth == 0:
                break
            k += 1
        i = k + 1
    out.append(text[i:])
    target = os.path.join(dest, os.path.normpath(path))
    os.makedirs(os.path.dirname(target), exist_ok=True)
    open(target, "w").write("".join(out))
PY
}

for path in native/DesignSystem "$@"; do
    # Listing the design system again is harmless: its files land in the same place.
    strip_previews "$path" "$work/sources"
done

# Builds a package module (and the package modules it imports) for iOS, once.
build_module() {
    local name=$1
    [ -e "$work/modules/$name.swiftmodule" ] && return
    local dir
    dir=$(ls -d Packages/*/Sources/"$name" 2>/dev/null | head -1 || true)
    [ -n "$dir" ] || return 0
    for dependency in $(grep -rhoE "^(@[a-zA-Z_]+ )*import [A-Za-z_]+" "$dir" | awk '{print $NF}' | sort -u || true); do
        [ "$dependency" != "$name" ] && build_module "$dependency"
    done
    xcrun --sdk iphonesimulator swiftc -emit-module -parse-as-library -module-name "$name" "${flags[@]}" \
        -emit-module-path "$work/modules/$name.swiftmodule" $(find "$dir" -name "*.swift") >/dev/null
}

for module in $(grep -rhoE "^(@[a-zA-Z_]+ )*import [A-Za-z_]+" "$work/sources" | awk '{print $NF}' | sort -u || true); do
    build_module "$module"
done

output=$(xcrun --sdk iphonesimulator swiftc -typecheck -parse-as-library -default-isolation MainActor "${flags[@]}" \
    $(find "$work/sources" -name "*.swift") 2>&1 || true)
diagnostics=$(echo "$output" | grep -E "(error|warning):" | sed -e "s|$work/sources/||" | sort -u || true)
if [ -n "$diagnostics" ]; then
    echo "$diagnostics"
fi
if echo "$output" | grep -q "error:"; then
    echo "iOS check failed" >&2
    exit 1
fi
echo "iOS check passed: native/DesignSystem $*"
