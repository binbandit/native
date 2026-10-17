#!/usr/bin/env bash
# Builds, signs, notarizes, packages and publishes a release of Native. docs/releasing.md has the
# whole picture and the one-time setup.
#
#   scripts/release/release.sh --channel stable|beta|nightly [options]
#
# Without --notarize or --publish this is a dry run: everything that stays on this Mac runs
# (archive, sign, package, appcast) and every step that talks to Apple or GitHub is printed instead.
#
#   --channel <name>         stable, beta or nightly (required)
#   --version <version>      marketing version, e.g. 1.4.0 or 1.5.0-beta.1. Stable and beta default
#                            to the v* tag at HEAD; nightly derives one from the last stable tag
#   --build-number <n>       CFBundleVersion (default: the number of commits on HEAD)
#   --notarize               also notarize and staple (talks to Apple, publishes nothing)
#   --publish                notarize, staple and publish to GitHub Releases
#   --plan                   print every command and run nothing
#   --identity <name>        signing identity (default: Developer ID Application, or ad hoc for a
#                            dry run on a Mac without one)
#   --ed-key-file <path>     Sparkle EdDSA private key file, or - for stdin (default: the Keychain)
#   --download-url-prefix <url>  where the appcast says archives live (default: the GitHub release)
#   --build-setting KEY=VALUE    extra xcodebuild setting, repeatable (local update tests)
#   --output <dir>           default: build/release/<channel>
#   --no-dmg                 skip the disk image
#
# Environment: NATIVE_NOTARY_PROFILE (notarytool keychain profile, default native-notary),
# NATIVE_KEYCHAIN (keychain holding the identity and profile, for CI), NATIVE_TEAM_ID,
# NATIVE_GITHUB_REPOSITORY (overrides Config/Shared.xcconfig), GH_TOKEN for --publish in CI.
set -euo pipefail
source "$(dirname "$0")/lib.sh"

channel="" version="" build_number="" identity="" key_file="" url_prefix="" output="" make_dmg=1
settings=()
while [ $# -gt 0 ]; do
    case $1 in
        --channel) channel=$2; shift ;;
        --version) version=$2; shift ;;
        --build-number) build_number=$2; shift ;;
        --notarize) [ "$MODE" = publish ] || MODE=notarize ;;
        --publish) MODE=publish ;;
        --plan) MODE=plan ;;
        --identity) identity=$2; shift ;;
        --ed-key-file) key_file=$2; shift ;;
        --download-url-prefix) url_prefix=$2; shift ;;
        --build-setting) settings+=("$2"); shift ;;
        --output) output=$2; shift ;;
        --no-dmg) make_dmg=0 ;;
        -h | --help) sed -n '2,29p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
        *) die "unknown option $1 (see --help)" ;;
    esac
    shift
done

cd "$ROOT"
repo=$(github_repository)
notary_profile=${NATIVE_NOTARY_PROFILE:-native-notary}
keychain_args=()
[ -n "${NATIVE_KEYCHAIN:-}" ] && keychain_args=(--keychain "$NATIVE_KEYCHAIN")

# MARK: - What to build

case $channel in
    stable | beta) configuration=Release product="Native" ;;
    nightly) configuration=Nightly product="Native Nightly" ;;
    *) die "--channel must be stable, beta or nightly" ;;
esac
asset_base=${product// /-}
[ -n "$build_number" ] || build_number=$(git rev-list --count HEAD)
sha=$(git rev-parse HEAD)

last_stable_tag() {
    git describe --tags --abbrev=0 --match 'v[0-9]*' --exclude '*-*' "$@" 2>/dev/null || true
}

if [ -z "$version" ]; then
    if [ "$channel" = nightly ]; then
        base=$(last_stable_tag HEAD)
        version="${base:-v0.1.0}"
        version="${version#v}-nightly.$(date -u +%Y%m%d).$(git rev-parse --short=7 HEAD)"
    else
        tag=$(git describe --tags --exact-match --match 'v[0-9]*' HEAD 2>/dev/null) || die "HEAD has no v* tag; pass --version"
        version=${tag#v}
    fi
fi
if [ "$channel" = beta ] && [[ $version != *-beta* ]]; then
    die "beta versions look like 1.5.0-beta.1 (got $version)"
fi
if [ "$channel" = stable ] && [[ $version == *-* ]]; then
    die "stable versions have no suffix (got $version); use --channel beta"
fi

tag="v$version"
[ "$channel" = nightly ] && tag=nightly
releases="https://github.com/$repo/releases"
[ -n "$url_prefix" ] || url_prefix="$releases/download/$tag/"
output=${output:-build/release/$channel}
archive="$output/$asset_base.xcarchive"
app="$output/$product.app"
# Nightly archives carry the build number so a download in flight never meets a replaced file.
if [ "$channel" = nightly ]; then zip_name="$asset_base-$build_number.zip" dmg_name="$asset_base.dmg"; else zip_name="$asset_base-$version.zip" dmg_name="$asset_base-$version.dmg"; fi

if [ "$MODE" = publish ]; then
    [[ $repo == *PLACEHOLDER* ]] && die "set NATIVE_GITHUB_REPOSITORY in Config/Shared.xcconfig before publishing (docs/releasing.md)"
    [ -n "$(xcconfig_value NATIVE_SPARKLE_PUBLIC_KEY Shared.xcconfig)" ] || die "set NATIVE_SPARKLE_PUBLIC_KEY in Config/Shared.xcconfig before publishing"
    [ -z "$(git status --porcelain)" ] || die "the working tree has changes; release from a clean checkout"
    require_tool gh "brew install gh"
fi

# Developer ID for anything that leaves this Mac; ad hoc is fine for a local dry run.
if [ -z "$identity" ]; then
    if security find-identity -v -p codesigning ${keychain_args[@]+"${keychain_args[@]}"} | grep -q "Developer ID Application"; then
        identity="Developer ID Application"
    elif [ "$MODE" = dry-run ] || [ "$MODE" = plan ]; then
        identity="-"
        warn "no Developer ID Application identity; signing ad hoc (fine for a dry run, not for users)"
    else
        die "no Developer ID Application identity in the keychain (docs/releasing.md, \"One-time setup\")"
    fi
fi
team=${NATIVE_TEAM_ID:-}
if [ -z "$team" ] && [ "$identity" != "-" ]; then
    team=$(security find-identity -v -p codesigning ${keychain_args[@]+"${keychain_args[@]}"} | sed -n "s/.*\"$identity.*(\([A-Z0-9]*\))\".*/\1/p" | head -1)
fi

log "$product $version (build $build_number) from ${sha:0:7}, $MODE"

# MARK: - Archive and sign

log "Archiving ($configuration)"
channel_condition=""
[ "$channel" = beta ] && channel_condition=NATIVE_BETA
# A secure timestamp is what notarization wants; ad hoc signatures can't carry one.
sign_flags=""
[ "$identity" = "-" ] || sign_flags="--timestamp${NATIVE_KEYCHAIN:+ --keychain $NATIVE_KEYCHAIN}"
run rm -rf "$archive" "$app"
run mkdir -p "$output"
run xcodebuild archive \
    -project native.xcodeproj -scheme native -configuration "$configuration" \
    -archivePath "$archive" -derivedDataPath "$output/DerivedData" -destination 'generic/platform=macOS' \
    MARKETING_VERSION="$version" CURRENT_PROJECT_VERSION="$build_number" \
    NATIVE_CHANNEL_CONDITION="$channel_condition" \
    CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY="$identity" DEVELOPMENT_TEAM="$team" \
    CODE_SIGN_INJECT_BASE_ENTITLEMENTS=NO OTHER_CODE_SIGN_FLAGS="$sign_flags" \
    ${settings[@]+"${settings[@]}"} -quiet
run ditto "$archive/Products/Applications/$product.app" "$app"
run codesign --verify --deep --strict --verbose=2 "$app"

# MARK: - Notarize and staple

notarize() {
    notary xcrun notarytool submit "$1" --keychain-profile "$notary_profile" ${keychain_args[@]+"${keychain_args[@]}"} --wait
}

log "Notarizing"
run ditto -c -k --sequesterRsrc --keepParent "$app" "$output/notarize.zip"
notarize "$output/notarize.zip"
notary xcrun stapler staple "$app"
notary spctl --assess --type execute --verbose=2 "$app"
run rm -f "$output/notarize.zip"

# MARK: - Package

log "Packaging"
run rm -rf "$output/appcast" "$output/$dmg_name"
run mkdir -p "$output/appcast"
# The update archive Sparkle installs, next to its notes; generate_appcast reads both.
run ditto -c -k --sequesterRsrc --keepParent "$app" "$output/appcast/$zip_name"
previous_tag=""
case $channel in
    stable) previous_tag=$(last_stable_tag "$sha^") ;;
    beta) previous_tag=$(git describe --tags --abbrev=0 --match 'v[0-9]*' "$sha^" 2>/dev/null || true) ;;
    nightly) git fetch --quiet --force origin tag nightly 2>/dev/null || true
        previous_tag=$(git rev-parse --verify --quiet nightly 2>/dev/null || true) ;;
esac
notes="$output/appcast/${zip_name%.zip}.md"
if [ "$MODE" = plan ]; then
    printf '  [plan] release notes since %s > %s\n' "${previous_tag:-the first commit}" "$notes" >&2
else
    "$ROOT/scripts/release/release-notes.sh" "$previous_tag" "$sha" >"$notes"
fi

if [ "$make_dmg" = 1 ]; then
    staging="$output/dmg"
    run rm -rf "$staging"
    run mkdir -p "$staging"
    run ditto "$app" "$staging/$product.app"
    run ln -s /Applications "$staging/Applications"
    run hdiutil create -quiet -volname "$product" -srcfolder "$staging" -ov -format ULFO "$output/$dmg_name"
    run rm -rf "$staging"
    [ "$identity" = "-" ] || run codesign --sign "$identity" --timestamp ${keychain_args[@]+"${keychain_args[@]}"} "$output/$dmg_name"
    notarize "$output/$dmg_name"
    notary xcrun stapler staple "$output/$dmg_name"
fi

# MARK: - Appcast

log "Generating the appcast"
feed="$releases/latest/download/appcast.xml"
[ "$channel" = nightly ] && feed="$releases/download/nightly/appcast.xml"
# Start from the published feed so earlier items (and the other channel's) stay in it.
if [ "$MODE" != plan ] && [[ $repo != *PLACEHOLDER* ]]; then
    curl -fsSL "$feed" -o "$output/appcast/appcast.xml" 2>/dev/null || log "No published feed yet; starting a new one"
fi
sparkle_bin=${SPARKLE_BIN:-$output/DerivedData/SourcePackages/artifacts/sparkle/Sparkle/bin}
appcast_args=(--download-url-prefix "$url_prefix" --embed-release-notes --full-release-notes-url "$releases")
[ "$channel" = beta ] && appcast_args+=(--channel beta)
[ "$channel" = nightly ] && appcast_args+=(--maximum-versions 1)
[ -n "$key_file" ] && appcast_args+=(--ed-key-file "$key_file")
# generate_keys keeps the private key in the login keychain under this service and account.
if [ -z "$key_file" ] && [ "$MODE" = dry-run ] && ! security find-generic-password -s https://sparkle-project.org -a ed25519 >/dev/null 2>&1; then
    warn "no Sparkle signing key in the keychain (docs/releasing.md, \"One-time setup\"); not signing an appcast"
    printf '  [dry run] would run: %s\n' "$(quoted "$sparkle_bin/generate_appcast" "${appcast_args[@]}" "$output/appcast")" >&2
else
    run "$sparkle_bin/generate_appcast" "${appcast_args[@]}" "$output/appcast"
fi

# MARK: - Publish

log "Publishing to $repo"
assets=("$output/appcast/$zip_name")
[ "$make_dmg" = 1 ] && assets+=("$output/$dmg_name")
notes_flag=(--notes-file "$notes")

if [ "$channel" = nightly ]; then
    if [ "$MODE" = publish ] && gh release view nightly --repo "$repo" >/dev/null 2>&1; then
        # The rolling release keeps its URL; its tag moves to this commit.
        remote gh api -X PATCH "repos/$repo/git/refs/tags/nightly" -f sha="$sha" -F force=true
        remote gh release edit nightly --repo "$repo" --title "Native Nightly" "${notes_flag[@]}"
    else
        remote gh release create nightly --repo "$repo" --prerelease --target "$sha" --title "Native Nightly" "${notes_flag[@]}"
    fi
    # Archives first, so the appcast never points at a file that isn't there yet.
    remote gh release upload nightly --repo "$repo" --clobber "${assets[@]}"
    remote gh release upload nightly --repo "$repo" --clobber "$output/appcast/appcast.xml"
    if [ "$MODE" = publish ]; then
        # Keep the newest two archives so downloads already in flight still finish.
        gh release view nightly --repo "$repo" --json assets --jq '.assets[].name' |
            grep -E "^$asset_base-[0-9]+\.zip$" | sort -t- -k3 -n | awk '{ a[NR] = $0 } END { for (i = 1; i <= NR - 2; i++) print a[i] }' |
            while read -r old; do run gh release delete-asset nightly "$old" --repo "$repo" --yes; done
    fi
else
    prerelease=()
    [ "$channel" = beta ] && prerelease=(--prerelease)
    # A draft with every asset, then published at once: the feed never sees a half-made release.
    remote gh release create "$tag" --repo "$repo" --draft --verify-tag --title "Native $version" \
        ${prerelease[@]+"${prerelease[@]}"} "${notes_flag[@]}" "${assets[@]}" "$output/appcast/appcast.xml"
    remote gh release edit "$tag" --repo "$repo" --draft=false
    if [ "$channel" = beta ]; then
        # Betas are prereleases, so releases/latest still points at the newest stable release.
        # The feed lives there, so it gets the appcast with this beta in it too.
        latest=""
        [ "$MODE" = publish ] && latest=$(gh api "repos/$repo/releases/latest" --jq .tag_name 2>/dev/null || true)
        if [ -n "$latest" ] || [ "$MODE" != publish ]; then
            remote gh release upload "${latest:-<latest stable tag>}" --repo "$repo" --clobber "$output/appcast/appcast.xml"
        else
            warn "there's no stable release yet, so beta users can't receive this update until there is one"
        fi
    fi
fi

log "Done. Artifacts are in $output"
