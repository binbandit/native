#!/usr/bin/env bash
# Compiles the configurations releases ship from, Release and Nightly, without signing, so a break
# that only shows up outside Debug (an unguarded #Preview fixture, a DEBUG-only helper) is caught
# before a release needs it. Like a release, it builds the terminal and the script runtime for real
# first (the first time fetches Zig, Ghostty and V8). Then checks each app against its size budget
# and that both made it in (size-check.sh, docs/app-size.md).
#
#   scripts/release/check.sh [--derived-data <dir>] [--source-packages <dir>]
#                            [--compilation-cache <dir>] [configuration...]
#
# Configurations default to Release and Nightly. It builds for arm64 only, like a release: the
# packages declare macOS 15 and would otherwise compile an x86_64 slice that nothing links. For CI,
# which caches both between runs: --source-packages keeps Swift package checkouts in a folder of their
# own (xcodebuild's -clonedSourcePackagesDirPath), and --compilation-cache turns on Xcode's
# compilation cache in that folder. The cache is content-addressed (a compile's inputs are its key),
# so a fresh DerivedData reuses every unchanged compile without incremental build state, and cached
# compiles replay their warnings, so the warnings gate still sees them.
set -euo pipefail
source "$(dirname "$0")/lib.sh"

derived=${TMPDIR:-/tmp}/native-release-check
packages=() caching=()
configurations=()
while [ $# -gt 0 ]; do
    case $1 in
        --derived-data) derived=$2; shift ;;
        --source-packages) packages=(-clonedSourcePackagesDirPath "$2"); shift ;;
        # Bounded: past 2 GB, Xcode starts a new generation and drops what later builds don't use.
        --compilation-cache) caching=(COMPILATION_CACHE_ENABLE_CACHING=YES "COMPILATION_CACHE_CAS_PATH=$2"
            COMPILATION_CACHE_LIMIT_SIZE=2G); shift ;;
        -h | --help) sed -n '2,17p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
        *) configurations+=("$1") ;;
    esac
    shift
done
[ ${#configurations[@]} -gt 0 ] || configurations=(Release Nightly)

cd "$ROOT"
build_embedded
for configuration in "${configurations[@]}"; do
    log "Building $configuration"
    run xcodebuild build -project native.xcodeproj -scheme native -configuration "$configuration" \
        -derivedDataPath "$derived" ${packages[@]+"${packages[@]}"} -destination 'platform=macOS' \
        CODE_SIGNING_ALLOWED=NO ARCHS=arm64 ${caching[@]+"${caching[@]}"} -quiet
done
log "$(printf '%s and ' "${configurations[@]}" | sed 's/ and $//') compiled"
run "$ROOT/scripts/release/size-check.sh" --built "$derived" "${configurations[@]}"
