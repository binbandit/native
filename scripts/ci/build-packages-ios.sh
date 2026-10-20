#!/bin/bash
# Builds every Swift package that declares iOS (`.iOS(` in its Package.swift) for the iOS Simulator,
# as the iOS workflow does (.github/workflows/ios.yml), so a package can't stop building for the iPad
# and the iPhone unnoticed. The Mac's own builds and tests never compile them for iOS.
#
#   scripts/ci/build-packages-ios.sh [--derived-data <dir>] [--source-packages <dir>]
#                                    [--compilation-cache <dir>] [package...]
#
# Packages default to all of them. Each builds its `<Package>-Package` scheme (every target), or its
# only scheme, into its own DerivedData under --derived-data (default $TMPDIR/native-ios-packages),
# with its log beside it as <package>.log, and then goes through scripts/check-warnings.sh: our own
# files build without warnings for iOS too. --source-packages and --compilation-cache are the same
# CI caches as scripts/release/check.sh's. Each package's output is a log group; a failing package is
# annotated with its name, the rest still build, and the run fails at the end.
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

failed=""
for name in "${names[@]}"; do
    echo "::group::$name"
    started=$SECONDS
    log="$derived/$name.log"
    package="$root/Packages/$name"
    schemes=$(cd "$package" && xcodebuild -list -json ${packages[@]+"${packages[@]}"} 2>/dev/null |
        jq -r '.workspace.schemes[]' || true)
    scheme=$(grep -x "$name-Package" <<<"$schemes" || head -1 <<<"$schemes")
    if [ -n "$scheme" ] && (cd "$package" && xcodebuild build -scheme "$scheme" \
        -destination 'generic/platform=iOS Simulator' -derivedDataPath "$derived/$name" \
        ${packages[@]+"${packages[@]}"} -skipPackagePluginValidation -skipMacroValidation \
        CODE_SIGNING_ALLOWED=NO ${caching[@]+"${caching[@]}"}) >"$log" 2>&1 && "$root/scripts/check-warnings.sh" "$log"; then
        echo "::endgroup::"
        echo "$name built for iOS in $((SECONDS - started))s"
    else
        grep -E '^[^[:space:]|].*error: ' "$log" | sort -u | head -30 || true
        echo "::endgroup::"
        echo "::error title=$name::Packages/$name doesn't build for the iOS Simulator (log: $log)"
        failed="$failed $name"
    fi
done
if [ -n "$failed" ]; then
    echo "Failed:$failed"
    exit 1
fi
