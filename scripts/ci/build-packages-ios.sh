#!/bin/bash
# Builds every Swift package that declares iOS (`.iOS(` in its Package.swift) for the iOS Simulator,
# as the iOS workflow does (.github/workflows/ios.yml), so a package can't stop building for the iPad
# and the iPhone unnoticed: the Mac's own builds and tests never compile them for iOS.
#
#   scripts/ci/build-packages-ios.sh [--derived-data <dir>] [--source-packages <dir>]
#                                    [--compilation-cache <dir>] [package...]
#
# Packages default to all of them. Each builds what it offers iOS (scheme() below) into its own
# DerivedData under --derived-data (default $TMPDIR/native-ios-packages), logs to <package>.log there,
# and goes through scripts/check-warnings.sh: our files build without warnings for iOS too.
# --source-packages and --compilation-cache are the CI caches scripts/release/check.sh takes. Each
# package's output is a log group; a failing package is annotated with its name, the rest still
# build, and the run fails at the end.
set -euo pipefail

root=$(git -C "$(dirname "$0")" rev-parse --show-toplevel)
derived=${TMPDIR:-/tmp}/native-ios-packages
packages=() caching=() names=()
while [ $# -gt 0 ]; do
    case $1 in
        --derived-data) derived=$2; shift ;;
        --source-packages) packages=(-clonedSourcePackagesDirPath "$2"); shift ;;
        --compilation-cache) caching=(COMPILATION_CACHE_ENABLE_CACHING=YES "COMPILATION_CACHE_CAS_PATH=$2"
            COMPILATION_CACHE_LIMIT_SIZE=2G); shift ;;
        -h | --help) sed -n '2,14p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
        -*) echo "unknown option $1" >&2; exit 2 ;;
        *) names+=("$1") ;;
    esac
    shift
done
if [ ${#names[@]} -eq 0 ]; then
    for manifest in "$root"/Packages/*/Package.swift; do
        grep -q '\.iOS(' "$manifest" && names+=("$(basename "$(dirname "$manifest")")")
    done
fi
mkdir -p "$derived"

# The scheme that builds what a package offers iOS: `<Package>-Package` (every target) or its only
# scheme. NativeHost also holds the Mac's host (NativeHostMac, native-host); a host runs agents, which
# iPadOS can't, so only its client builds there.
scheme() {
    local name=$1 schemes
    if [ "$name" = NativeHost ]; then
        echo NativeHostClient
        return
    fi
    schemes=$(cd "$root/Packages/$name" && xcodebuild -list -json ${packages[@]+"${packages[@]}"} 2>/dev/null |
        jq -r '.workspace.schemes[]' || true)
    grep -x "$name-Package" <<<"$schemes" || head -1 <<<"$schemes"
}

build() {
    local name=$1 scheme log="$derived/$1.log"
    scheme=$(scheme "$name")
    [ -n "$scheme" ] || { echo "error: no scheme found for Packages/$name"; return 1; }
    (cd "$root/Packages/$name" && xcodebuild build -scheme "$scheme" -destination 'generic/platform=iOS Simulator' \
        -derivedDataPath "$derived/$name" ${packages[@]+"${packages[@]}"} -skipPackagePluginValidation \
        -skipMacroValidation CODE_SIGNING_ALLOWED=NO ${caching[@]+"${caching[@]}"}) >"$log" 2>&1 || {
        grep -E '^[^[:space:]|].*error: ' "$log" | sort -u | head -30
        return 1
    }
    "$root/scripts/check-warnings.sh" "$log"
}

failed=""
for name in "${names[@]}"; do
    echo "::group::$name"
    started=$SECONDS
    if build "$name"; then
        echo "::endgroup::"
        echo "$name built for iOS in $((SECONDS - started))s"
    else
        echo "::endgroup::"
        echo "::error title=$name::Packages/$name doesn't build for the iOS Simulator (log: $derived/$name.log)"
        failed="$failed $name"
    fi
done
if [ -n "$failed" ]; then
    echo "Failed:$failed"
    exit 1
fi
