#!/bin/bash
# Package snapshots and compiler caches shared by isolated Debug builds.
# Mutable SwiftPM workspace state and Xcode build products stay in each instance's DerivedData.
set -euo pipefail

mode=${1:?usage: build-cache.sh prepare|publish repo derived}
root=${2:?missing repository}
derived=${3:?missing DerivedData}
cache=${NATIVE_DEV_CACHE:-$HOME/Library/Caches/native-build/isolated}
resolved="$root/native.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved"
# Include local manifests and the project: the SwiftPM graph can change without different pins.
package_key=$({
    cat "$resolved" "$root/native.xcodeproj/project.pbxproj"
    find "$root/Packages" -name Package.swift -not -path '*/.build/*' -print | LC_ALL=C sort | while IFS= read -r manifest; do
        printf '%s\n' "${manifest#"$root/"}"
        cat "$manifest"
    done
    xcrun swiftc --version 2>/dev/null
} | shasum -a 256 | awk '{print $1}')
snapshot="$cache/packages-v2/$package_key"
packages="$derived/SourcePackages"

clone_folder() {
    # APFS clones share data blocks, never mutable inodes. Fall back for non-APFS cache volumes.
    mkdir -p "$2"
    cp -cR "$1/." "$2/" 2>/dev/null || cp -R "$1/." "$2/"
}

case "$mode" in
prepare)
    # Restore a private workspace state, remapping its local package and binary artifact paths.
    if [ ! -e "$packages" ] && [ -d "$snapshot" ]; then
        staged="$derived/SourcePackages.seed.$$"
        trap 'rm -rf "$staged"' EXIT
        mkdir -p "$staged"
        for folder in repositories checkouts artifacts; do
            [ ! -d "$snapshot/$folder" ] || clone_folder "$snapshot/$folder" "$staged/$folder"
        done
        [ ! -f "$snapshot/workspace-state.json" ] || cp "$snapshot/workspace-state.json" "$staged/"
        python3 "$root/scripts/dev/build-cache-state.py" "$staged" \
            '@NATIVE_REPO@' '@NATIVE_PACKAGES@' "$root" "$packages"
        mv "$staged" "$packages"
        echo "seeded Swift packages from shared cache" >&2
    fi
    ;;
publish)
    [ ! -e "$snapshot" ] || exit 0
    [ -d "$packages/checkouts" ] || exit 0
    # A locally edited dependency must never become another worktree's pinned source.
    for checkout in "$packages/checkouts"/*; do
        [ -d "$checkout/.git" ] || exit 0
        [ -z "$(git -C "$checkout" status --porcelain --untracked-files=all)" ] || exit 0
    done
    mkdir -p "$cache/packages-v2"
    # Readers see only complete snapshots. First successful publisher wins for these exact pins.
    if [ -z "${NATIVE_DEV_CACHE_LOCKED:-}" ]; then
        exec env NATIVE_DEV_CACHE_LOCKED=1 lockf -k "$cache/packages-v2/.publish.lock" "$0" "$@"
    fi
    [ ! -e "$snapshot" ] || exit 0
    staged=$(mktemp -d "$cache/packages-v2/.seed.XXXXXX")
    trap 'rm -rf "$staged"' EXIT
    for folder in repositories checkouts artifacts; do
        [ ! -d "$packages/$folder" ] || clone_folder "$packages/$folder" "$staged/$folder"
    done
    [ ! -f "$packages/workspace-state.json" ] || cp "$packages/workspace-state.json" "$staged/"
    python3 "$root/scripts/dev/build-cache-state.py" "$staged" \
        "$root" "$packages" '@NATIVE_REPO@' '@NATIVE_PACKAGES@'
    # Validate the private copy, so committed edits cannot masquerade as the recorded pin.
    python3 "$root/scripts/dev/build-cache-state.py" --validate "$staged" "$resolved" || exit 0
    mv "$staged" "$snapshot"
    ;;
*) echo "unknown cache action: $mode" >&2; exit 2 ;;
esac
