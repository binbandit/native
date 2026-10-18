#!/usr/bin/env bash
# Builds the standalone `native-host` and its signed host feed, for hosts that run without the app
# (a Linux run box, a Mac with only native-host) and update themselves. release.sh runs it; run it
# alone to try the host part. docs/releasing.md, "Remote updates".
#
#   scripts/release/host.sh --channel <name> --version <v> --build-number <n> --output <dir>
#       [--identity <name>] [--ed-key-file <path>] [--notes <file>] [--plan | --notarize]
#
# Writes <output>/host/: native-host-<build>-macos-universal, host-feed[-beta].json and its .sig.
# Linux binaries join the feed once the host core builds there (TODO(linux) in .github/workflows).
set -euo pipefail
source "$(dirname "$0")/lib.sh"

channel="" version="" build_number="" output="" identity="-" key_file="" notes=""
while [ $# -gt 0 ]; do
    case $1 in
        --channel) channel=$2; shift ;;
        --version) version=$2; shift ;;
        --build-number) build_number=$2; shift ;;
        --output) output=$2; shift ;;
        --identity) identity=$2; shift ;;
        --ed-key-file) key_file=$2; shift ;;
        --notes) notes=$2; shift ;;
        --plan) MODE=plan ;;
        --notarize) MODE=notarize ;;
        --publish) MODE=publish ;;
        -h | --help) sed -n '2,10p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
        *) die "unknown option $1 (see --help)" ;;
    esac
    shift
done
[ -n "$channel" ] && [ -n "$version" ] && [ -n "$build_number" ] && [ -n "$output" ] || die "see --help"
require_tool jq "brew install jq"

cd "$ROOT"
repo=$(github_repository)
releases="https://github.com/$repo/releases"
tag="v$version"
[ "$channel" = nightly ] && tag=nightly
host="$output/host"
binary_name="native-host-$build_number-macos-universal"
feed_name="host-feed.json"
[ "$channel" = beta ] && feed_name="host-feed-beta.json"
sparkle_bin=${SPARKLE_BIN:-$output/DerivedData/SourcePackages/artifacts/sparkle/Sparkle/bin}
keychain_args=()
[ -n "${NATIVE_KEYCHAIN:-}" ] && keychain_args=(--keychain "$NATIVE_KEYCHAIN")

log "Building native-host $version (build $build_number), macOS universal"
run rm -rf "$host"
run mkdir -p "$host"
run swift build -c release --package-path Packages/NativeHost --product native-host \
    --arch arm64 --arch x86_64 --scratch-path "$output/host-build"
run cp "$output/host-build/apple/Products/Release/native-host" "$host/$binary_name"
if [ "$identity" = "-" ]; then
    run codesign --force --sign - --identifier native-host "$host/$binary_name"
else
    run codesign --force --sign "$identity" --identifier native-host --options runtime --timestamp \
        ${keychain_args[@]+"${keychain_args[@]}"} "$host/$binary_name"
fi

# Bare binaries can't carry a stapled ticket; notarizing registers it so Gatekeeper finds it online
# when the binary is copied to a Mac by hand.
run ditto -c -k "$host/$binary_name" "$output/host-notarize.zip"
notary xcrun notarytool submit "$output/host-notarize.zip" --keychain-profile "${NATIVE_NOTARY_PROFILE:-native-notary}" \
    ${keychain_args[@]+"${keychain_args[@]}"} --wait
run rm -f "$output/host-notarize.zip"

sign() {
    local args=(-p)
    [ -n "$key_file" ] && args+=(--ed-key-file "$key_file")
    "$sparkle_bin/sign_update" "${args[@]}" "$1"
}

log "Writing the host feed"
if [ "$MODE" = plan ]; then
    printf '  [plan] sign %s, write %s and %s.sig\n' "$binary_name" "$feed_name" "$feed_name" >&2
    exit 0
fi
if [ -z "$key_file" ] && ! security find-generic-password -s https://sparkle-project.org -a ed25519 >/dev/null 2>&1; then
    warn "no Sparkle signing key (docs/releasing.md, \"One-time setup\"); not writing a host feed"
    exit 0
fi
signature=$(sign "$host/$binary_name")
jq -n \
    --arg channel "$channel" --arg version "$version" --arg build "$build_number" \
    --arg date "$(date -u +%Y-%m-%dT%H:%M:%SZ)" --rawfile notes "${notes:-/dev/null}" \
    --arg notesURL "$releases/tag/$tag" --arg url "$releases/download/$tag/$binary_name" \
    --argjson size "$(stat -f %z "$host/$binary_name")" \
    --arg sha256 "$(shasum -a 256 "$host/$binary_name" | cut -d' ' -f1)" --arg signature "$signature" \
    '{schema: 1, channel: $channel, version: $version, build: $build, date: $date,
      notes: (if $notes == "" then null else $notes end), releaseNotesURL: $notesURL,
      assets: [{platform: "macos", arch: "universal", url: $url, size: $size, sha256: $sha256, edSignature: $signature}]}' \
    >"$host/$feed_name"
sign "$host/$feed_name" >"$host/$feed_name.sig"
log "Host feed ready: $host/$feed_name"
