#!/bin/bash
# Type-checks app folders for iPadOS, until the app has an iPadOS destination.
#
#   scripts/check-ios.sh native/DesignSystem native/Views/Sidebar
#
# Run from anywhere in the repo, with paths from its root. Starts with the given folders and
# native/DesignSystem, then adds app declarations Swift reports missing and their extensions.
# Imported local package modules are built recursively for the iOS simulator. Packages with
# resources or remote dependencies use xcodebuild through the shared build queue.
# Uses Swift 6 and the app's isolation/import settings; #Preview bodies are removed with their
# line numbers preserved. Dependency errors remain visible: a Mac-only dependency blocks its
# consumers until it has an iPad adapter. No declarations are stubbed and no errors are hidden.
# NATIVE_IOS_CHECK_CACHE overrides the incremental package cache location.
# CI also checks warnings with scripts/check-warnings.sh (.github/workflows/ios.yml).
set -euo pipefail

if [ $# -eq 0 ]; then
    echo "usage: scripts/check-ios.sh <folder or file>…" >&2
    exit 2
fi

root=$(git -C "$(dirname "$0")" rev-parse --show-toplevel)
cd "$root"
work=$(mktemp -d -t native-check-ios)
packages=${NATIVE_IOS_CHECK_CACHE:-${TMPDIR:-/tmp}/native-check-ios-packages}
lock=""
trap 'rm -rf "$work"; [ -z "$lock" ] || rmdir "$lock" 2>/dev/null' EXIT
mkdir -p "$work/sources" "$work/modules"

sdk=$(xcrun --sdk iphonesimulator --show-sdk-path)
target="arm64-apple-ios27.0-simulator"
# Packages build with their manifests' defaults (Swift 6); the app's own settings come at the end.
flags=(-swift-version 6 -target "$target" -sdk "$sdk" -I "$work/modules")
mapped=" "

python3 scripts/check-ios-sources.py "$work/sources" native/DesignSystem "$@" >"$work/added"

# Builds a package with xcodebuild for the simulator and imports its products, for packages swiftc
# alone can't build. The cache makes reruns incremental; parallel checks take turns on it.
build_package() {
    local package=$1 name=$2 derived
    derived="$packages/$(basename "$package")"
    mkdir -p "$packages"
    until mkdir "$derived.lock" 2>/dev/null; do sleep 1; done
    lock="$derived.lock"
    if ! (cd "$package" && "$root/scripts/dev/build-slot.sh" -scheme "$name" -destination "generic/platform=iOS Simulator" \
        -derivedDataPath "$derived" build -quiet) >"$derived.log" 2>&1; then
        grep -E "error:" "$derived.log" | sort -u | head -20 >&2 || true
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

package_manifest() {
    local manifest="$work/$(basename "$1").json"
    if [ ! -e "$manifest" ]; then
        swift package --package-path "$1" dump-package >"$manifest" || return
    fi
    echo "$manifest"
}

imported_modules() {
    local module dir manifest candidates availability=()
    swift_files "$1"
    [ ${#files[@]} -gt 0 ] || return 0
    # A fresh module directory must not turn an intended local dependency's canImport guard off.
    # Bootstrap iOS library targets named by those guards; SDK and Mac-only modules stay real.
    candidates=$(python3 - ${files[@]+"${files[@]}"} <<'PY'
import re, sys
names = set()
for path in sys.argv[1:]:
    for line in open(path):
        if line.lstrip().startswith(("#if ", "#elseif ")):
            names.update(re.findall(r"\bcanImport\s*\(\s*(\w+)", line))
print("\n".join(sorted(names)))
PY
    )
    for module in $candidates; do
        dir=$(ls -d Packages/*/Sources/"$module" 2>/dev/null | head -1 || true)
        [ -n "$dir" ] || continue
        manifest=$(package_manifest "${dir%/Sources/*}")
        if python3 - "$manifest" "$module" <<'PY'
import json, sys
package = json.load(open(sys.argv[1]))
platforms = package["platforms"]
target = next((t for t in package["targets"] if t["name"] == sys.argv[2]), {})
available = (not platforms or any(p["platformName"] == "ios" for p in platforms)) and target.get("type") == "regular"
sys.exit(0 if available else 1)
PY
        then
            echo "$module"
            availability+=(-module-can-import "$module")
        fi
    done
    # Availability overrides apply only to discovery. The final check uses actual built modules.
    xcrun --sdk iphonesimulator swiftc -frontend -emit-imported-modules -module-name NativeIOSImports "${flags[@]}" \
        ${availability[@]+"${availability[@]}"} ${files[@]+"${files[@]}"} | sort -u
}

# Builds a package module (and the package modules it imports) for iOS, once.
build_module() {
    local name=$1
    [ -e "$work/modules/$name.swiftmodule" ] || [ -e "$work/modules/$name.package" ] && return
    local dir dependencies manifest
    dir=$(ls -d Packages/*/Sources/"$name" 2>/dev/null | head -1 || true)
    [ -n "$dir" ] || return 0
    local package=${dir%/Sources/*}
    manifest=$(package_manifest "$package")
    # Test fixtures do not make a library target need a resource bundle. Only build the package
    # when the imported target needs resources, or SwiftPM must resolve remote dependencies.
    if python3 - "$manifest" "$name" <<'PY'
import json, sys
package = json.load(open(sys.argv[1]))
target = next(t for t in package["targets"] if t["name"] == sys.argv[2])
needs_build = target.get("resources") or any("sourceControl" in d for d in package["dependencies"])
sys.exit(0 if needs_build else 1)
PY
    then
        build_package "$package" "$name"
        return
    fi
    dependencies=$(imported_modules "$dir")
    for dependency in $dependencies; do
        [ "$dependency" != "$name" ] && build_module "$dependency"
    done
    swift_files "$dir"
    # A target with no Swift in it (a C library) has no Swift module to emit.
    [ ${#files[@]} -gt 0 ] || return 0
    xcrun --sdk iphonesimulator swiftc -emit-module -parse-as-library -module-name "$name" "${flags[@]}" \
        -emit-module-path "$work/modules/$name.swiftmodule" ${files[@]+"${files[@]}"} >/dev/null
}

while :; do
    modules=$(imported_modules "$work/sources")
    for module in $modules; do
        build_module "$module"
    done

    swift_files "$work/sources"
    status=0
    # One frontend checks every file, so all missing declarations can be resolved in one pass.
    xcrun --sdk iphonesimulator swiftc -frontend -typecheck -module-name native -parse-as-library -default-isolation MainActor \
        -enable-upcoming-feature MemberImportVisibility "${flags[@]}" ${files[@]+"${files[@]}"} \
        >"$work/diagnostics" 2>&1 || status=$?
    python3 scripts/check-ios-sources.py "$work/sources" --diagnostics "$work/diagnostics" >"$work/added"
    [ -s "$work/added" ] || break
    echo "Including $(wc -l <"$work/added" | tr -d ' ') app dependency files" >&2
done

# Keep only diagnostic headers, not the duplicate inline annotations in Swift's source excerpts.
grep -E '^[^|]*:[0-9]+:[0-9]+: (error|warning):|^<unknown>:0: (error|warning):|^error:' "$work/diagnostics" |
    sed -e "s|$work/sources/|$root/|" | sort -u || true
if [ "$status" -ne 0 ]; then
    # A compiler crash or driver failure may have no normal diagnostic header.
    if ! grep -q 'error:' "$work/diagnostics"; then cat "$work/diagnostics"; fi
    echo "iOS check failed" >&2
    exit "$status"
fi
echo "iOS check passed: native/DesignSystem $* (including app dependencies)"
