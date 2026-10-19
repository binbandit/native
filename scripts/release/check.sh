#!/usr/bin/env bash
# Compiles the configurations releases ship from, Release and Nightly, without signing, so a break
# that only shows up outside Debug (an unguarded #Preview fixture, a DEBUG-only helper) is caught
# before a release needs it. Then checks each app against its size budget (size.sh,
# docs/app-size.md).
#
#   scripts/release/check.sh [--derived-data <dir>] [configuration...]   # default: Release Nightly
set -euo pipefail
source "$(dirname "$0")/lib.sh"

derived=${TMPDIR:-/tmp}/native-release-check
configurations=()
while [ $# -gt 0 ]; do
    case $1 in
        --derived-data) derived=$2; shift ;;
        -h | --help) sed -n '2,7p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
        *) configurations+=("$1") ;;
    esac
    shift
done
[ ${#configurations[@]} -gt 0 ] || configurations=(Release Nightly)

cd "$ROOT"
for configuration in "${configurations[@]}"; do
    log "Building $configuration"
    run xcodebuild build -project native.xcodeproj -scheme native -configuration "$configuration" \
        -derivedDataPath "$derived" -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO -quiet
done
log "Release and Nightly compile"
for configuration in "${configurations[@]}"; do
    product=Native
    [ "$configuration" = Nightly ] && product="Native Nightly"
    run "$ROOT/scripts/release/size.sh" "$derived/Build/Products/$configuration/$product.app"
done
