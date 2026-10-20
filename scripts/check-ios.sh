#!/bin/bash
# Type-checks app folders for iPadOS, until the app has an iPadOS destination.
#
#   scripts/check-ios.sh native/DesignSystem native/Views/Sidebar
#
# Run from anywhere in the repo, with paths from its root. Compiles the given folders together with
# native/DesignSystem (every feature uses it) against the iOS simulator SDK in Swift 6 mode with the
# app's settings (MainActor by default, member import visibility). `#Preview` blocks are stripped,
# since the preview macro isn't available outside Xcode. Swift packages the files import (ACP, Git,
# …) are built for iOS first from Packages/*/Sources, with their own settings; a package SwiftPM has
# to build (remote dependencies or resources, like CodeThemes and its tree-sitter grammars) is built
# with xcodebuild for the simulator into a cache kept between runs. Code that uses other app folders
# needs those folders listed too. Prints the errors and warnings at their files' real paths, and exits
# non-zero if there are errors. CI also fails on warnings, by passing the output to
# scripts/check-warnings.sh (.github/workflows/ios.yml).
set -euo pipefail

if [ $# -eq 0 ]; then
    echo "usage: scripts/check-ios.sh <folder or file>…" >&2
    exit 2
fi

root=$(git -C "$(dirname "$0")" rev-parse --show-toplevel)
cd "$root"
work=$(mktemp -d -t native-check-ios)
packages=${TMPDIR:-/tmp}/native-check-ios-packages
lock=""
trap 'rm -rf "$work"; [ -z "$lock" ] || rmdir "$lock" 2>/dev/null' EXIT
mkdir -p "$work/sources" "$work/modules"

sdk=$(xcrun --sdk iphonesimulator --show-sdk-path)
target="arm64-apple-ios27.0-simulator"
# Packages build with their manifests' defaults (Swift 6); the app's own settings come at the end.
flags=(-swift-version 6 -target "$target" -sdk "$sdk" -I "$work/modules")
mapped=" "

# Copies Swift files into $2 with #Preview blocks removed, at their paths in the repository.
strip_previews() {
    python3 - "$1" "$2" <<'PY'
import os, sys
src, dest = os.path.relpath(sys.argv[1]), sys.argv[2]
if src.startswith("..") or not os.path.exists(src):
    sys.exit(f"{sys.argv[1]}: no such folder or file in the repository")
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

# Builds a package with xcodebuild for the simulator and imports its products, for packages swiftc
# alone can't build. The cache makes reruns incremental; parallel checks take turns on it.
build_package() {
    local package=$1 name=$2 derived
    derived="$packages/$(basename "$package")"
    mkdir -p "$packages"
    until mkdir "$derived.lock" 2>/dev/null; do sleep 1; done
    lock="$derived.lock"
    if ! (cd "$package" && xcodebuild -scheme "$name" -destination "generic/platform=iOS Simulator" \
        -derivedDataPath "$derived" build -quiet) >"$derived.log" 2>&1; then
        grep -E "error:" "$derived.log" | sort -u | head -20 >&2
        echo "building $package for iOS failed; full log: $derived.log" >&2
        exit 1
    fi
    rmdir "$lock"
    lock=""
    # Its Swift modules, and the frameworks it links as binaries (Sentry).
    flags+=(-I "$derived/Build/Products/Debug-iphonesimulator" -F "$derived/Build/Products/Debug-iphonesimulator")
    for map in "$derived"/Build/Intermediates.noindex/GeneratedModuleMaps-iphonesimulator/*.modulemap; do
        # Packages built this way bring their dependencies (Exec, say) along: each module maps once.
        [ -e "$map" ] && [[ $mapped != *" $(basename "$map") "* ]] || continue
        mapped+="$(basename "$map") "
        flags+=(-Xcc "-fmodule-map-file=$map")
    done
    touch "$work/modules/$name.package"
}

# The Swift files under a folder, into the array `files`. Expand it as ${files[@]+"${files[@]}"}:
# macOS's bash 3.2 calls an empty array unbound under `set -u`.
swift_files() {
    files=()
    while IFS= read -r -d '' file; do files+=("$file"); done < <(find "$1" -name "*.swift" -print0)
}

# Builds a package module (and the package modules it imports) for iOS, once.
build_module() {
    local name=$1
    [ -e "$work/modules/$name.swiftmodule" ] || [ -e "$work/modules/$name.package" ] && return
    local dir
    dir=$(ls -d Packages/*/Sources/"$name" 2>/dev/null | head -1 || true)
    [ -n "$dir" ] || return 0
    local package=${dir%/Sources/*}
    if grep -qE "\.package\(url:|resources:" "$package/Package.swift"; then
        build_package "$package" "$name"
        return
    fi
    for dependency in $(grep -rhoE "^(@[a-zA-Z_]+ )*import [A-Za-z_]+" "$dir" | awk '{print $NF}' | sort -u || true); do
        [ "$dependency" != "$name" ] && build_module "$dependency"
    done
    swift_files "$dir"
    # A target with no Swift in it (a C library) has no Swift module to emit.
    [ ${#files[@]} -gt 0 ] || return 0
    xcrun --sdk iphonesimulator swiftc -emit-module -parse-as-library -module-name "$name" "${flags[@]}" \
        -emit-module-path "$work/modules/$name.swiftmodule" ${files[@]+"${files[@]}"} >/dev/null
}

for module in $(grep -rhoE "^(@[a-zA-Z_]+ )*import [A-Za-z_]+" "$work/sources" | awk '{print $NF}' | sort -u || true); do
    build_module "$module"
done

swift_files "$work/sources"
output=$(xcrun --sdk iphonesimulator swiftc -typecheck -parse-as-library -default-isolation MainActor \
    -enable-upcoming-feature MemberImportVisibility "${flags[@]}" ${files[@]+"${files[@]}"} 2>&1 || true)
# At their real paths, so scripts/check-warnings.sh can read a log of this the way it reads a build's.
diagnostics=$(echo "$output" | grep -E "(error|warning):" | sed -e "s|$work/sources/|$root/|" | sort -u || true)
if [ -n "$diagnostics" ]; then
    echo "$diagnostics"
fi
if echo "$output" | grep -q "error:"; then
    echo "iOS check failed" >&2
    exit 1
fi
echo "iOS check passed: native/DesignSystem $*"
