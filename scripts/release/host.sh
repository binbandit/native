#!/usr/bin/env bash
# Builds the standalone `native-host` and its signed host feed, for hosts that run without the app
# (a Linux run box, a Mac with only native-host) and update themselves. release.sh runs it; run it
# alone to try the host part. docs/releasing.md, "Remote updates".
#
#   scripts/release/host.sh --channel <name> --version <v> --build-number <n> --output <dir>
#       [--identity <name>] [--ed-key-file <path>] [--notes <file>] [--linux <dir>] [--plan | --notarize]
#
# Writes <output>/host/: native-host-<build>-macos-universal (stripped), host-feed[-beta].json and its
# .sig, and the binary's symbols to <output>/host-dSYMs.
# --linux adds the native-host-linux-<arch> binaries in <dir> (built by CI; TODO(linux)).
set -euo pipefail
source "$(dirname "$0")/lib.sh"

channel="" version="" build_number="" output="" identity="-" key_file="" notes="" linux=""
while [ $# -gt 0 ]; do
    case $1 in
        --channel) channel=$2; shift ;;
        --version) version=$2; shift ;;
        --build-number) build_number=$2; shift ;;
        --output) output=$2; shift ;;
        --identity) identity=$2; shift ;;
        --ed-key-file) key_file=$2; shift ;;
        --notes) notes=$2; shift ;;
        --linux) linux=$2; shift ;;
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
# A bare binary has no bundle, so its identity, version, channel, feed and signing key travel in an
# embedded Info.plist, which Bundle.main reads like an app's.
public_key=${NATIVE_SPARKLE_PUBLIC_KEY:-$(xcconfig_value NATIVE_SPARKLE_PUBLIC_KEY Shared.xcconfig)}
feed_url="$releases/latest/download/$feed_name"
[ "$channel" = nightly ] && feed_url="$releases/download/nightly/$feed_name"
info="$output/host-Info.plist"
if [ "$MODE" != plan ]; then
    plutil -create xml1 "$info"
    for pair in "CFBundleIdentifier=native-host" "CFBundleName=Native Host" "CFBundleShortVersionString=$version" \
        "CFBundleVersion=$build_number" "NativeChannel=$channel" "NativeHostFeedURL=$feed_url" \
        "SUPublicEDKey=$public_key"; do
        plutil -insert "${pair%%=*}" -string "${pair#*=}" "$info"
    done
fi
run swift build -c release --package-path Packages/NativeHost --product native-host \
    --arch arm64 --arch x86_64 --scratch-path "$output/host-build" \
    -Xlinker -sectcreate -Xlinker __TEXT -Xlinker __info_plist -Xlinker "$info"
# Ask SwiftPM where it put the binary; the folder differs between toolchains.
bin_path=$output/host-build/out/Products/Release
[ "$MODE" = plan ] || bin_path=$(swift build -c release --package-path Packages/NativeHost --arch arm64 --arch x86_64 \
    --scratch-path "$output/host-build" --show-bin-path)
run cp "$bin_path/native-host" "$host/$binary_name"
# Every symbol goes into a dSYM, made while SwiftPM's object files are still there, then the binary
# hosts download is stripped (about 10.5 to 4.6 MB). release.sh sends the dSYM to Sentry with the
# app's, so a host's crash log can still be symbolicated.
run rm -rf "$output/host-dSYMs"
run mkdir -p "$output/host-dSYMs"
run dsymutil "$host/$binary_name" -o "$output/host-dSYMs/$binary_name.dSYM"
run strip "$host/$binary_name"
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
# One feed entry per binary: the universal macOS build, plus any Linux builds CI made.
entry() {
    jq -n --arg platform "$2" --arg arch "$3" --arg url "$releases/download/$tag/$(basename "$1")" \
        --argjson size "$(wc -c <"$1" | tr -d ' ')" --arg sha256 "$(shasum -a 256 "$1" | cut -d' ' -f1)" \
        --arg signature "$(sign "$1")" \
        '{platform: $platform, arch: $arch, url: $url, size: $size, sha256: $sha256, edSignature: $signature}'
}
entries=$(entry "$host/$binary_name" macos universal)
if [ -n "$linux" ]; then
    for file in "$linux"/native-host-linux-*; do
        [ -e "$file" ] || continue
        arch=${file##*-linux-}
        cp "$file" "$host/native-host-$build_number-linux-$arch"
        entries+=$'\n'$(entry "$host/native-host-$build_number-linux-$arch" linux "$arch")
    done
fi
jq -n \
    --arg channel "$channel" --arg version "$version" --arg build "$build_number" \
    --arg date "$(date -u +%Y-%m-%dT%H:%M:%SZ)" --rawfile notes "${notes:-/dev/null}" \
    --arg notesURL "$releases/tag/$tag" --argjson assets "$(jq -s . <<<"$entries")" \
    '{schema: 1, channel: $channel, version: $version, build: $build, date: $date,
      notes: (if $notes == "" then null else $notes end), releaseNotesURL: $notesURL, assets: $assets}' \
    >"$host/$feed_name"
sign "$host/$feed_name" >"$host/$feed_name.sig"
log "Host feed ready: $host/$feed_name"
