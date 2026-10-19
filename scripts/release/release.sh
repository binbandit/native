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
#   --rehearse               everything --publish does except publishing: its checks, notarizing,
#                            the appcast with its deltas, and a Sentry check that uploads nothing
#   --publish                notarize, staple and publish to GitHub Releases
#   --plan                   print every command and run nothing
#   --identity <name>        signing identity (default: Developer ID Application, or ad hoc for a
#                            dry run on a Mac without one)
#   --ed-key-file <path>     Sparkle EdDSA private key file, or - for stdin (default: the Keychain)
#   --download-url-prefix <url>  where the appcast says archives live (default: the GitHub release)
#   --build-setting KEY=VALUE    extra xcodebuild setting, repeatable (local update tests)
#   --output <dir>           default: $TMPDIR/native-release/<channel>, outside the repo so quicksaves
#                            never pick up archives
#   --no-dmg                 skip the disk image
#
# Environment: NATIVE_NOTARY_PROFILE (notarytool keychain profile, default native-notary),
# NATIVE_KEYCHAIN (keychain holding the identity and profile, for CI), NATIVE_TEAM_ID,
# NATIVE_GITHUB_REPOSITORY and NATIVE_SPARKLE_PUBLIC_KEY (override Config/Shared.xcconfig),
# NATIVE_SENTRY_DSN and SENTRY_AUTH_TOKEN (official builds), GH_TOKEN in CI,
# NATIVE_LINUX_HOST_DIR (native-host-linux-<arch> binaries to add to the host feed).
set -euo pipefail
source "$(dirname "$0")/lib.sh"

channel="" version="" build_number="" identity="" key_file="" url_prefix="" output="" make_dmg=1
settings=()
while [ $# -gt 0 ]; do
    case $1 in
        --channel) channel=$2; shift ;;
        --version) version=$2; shift ;;
        --build-number) build_number=$2; shift ;;
        --notarize) [ "$MODE" = publish ] || [ "$MODE" = rehearse ] || MODE=notarize ;;
        --rehearse) [ "$MODE" = publish ] || MODE=rehearse ;;
        --publish) MODE=publish ;;
        --plan) MODE=plan ;;
        --identity) identity=$2; shift ;;
        --ed-key-file) key_file=$2; shift ;;
        --download-url-prefix) url_prefix=$2; shift ;;
        --build-setting) settings+=("$2"); shift ;;
        --output) output=$2; shift ;;
        --no-dmg) make_dmg=0 ;;
        -h | --help) sed -n '2,33p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
        *) die "unknown option $1 (see --help)" ;;
    esac
    shift
done

cd "$ROOT"
repo=$(github_repository)
# The key every installed copy checks updates against. Official builds get it from the environment
# (CI's NATIVE_SPARKLE_PUBLIC_KEY variable), so a build from source never trusts Native's feed.
public_key=${NATIVE_SPARKLE_PUBLIC_KEY:-$(xcconfig_value NATIVE_SPARKLE_PUBLIC_KEY Shared.xcconfig)}
notary_profile=${NATIVE_NOTARY_PROFILE:-native-notary}
keychain_args=()
[ -n "${NATIVE_KEYCHAIN:-}" ] && keychain_args=(--keychain "$NATIVE_KEYCHAIN")
notary_args=(--keychain-profile "$notary_profile" ${keychain_args[@]+"${keychain_args[@]}"})
# `security find-identity` takes the keychain as a plain argument, not --keychain.
identities() {
    security find-identity -v -p codesigning ${NATIVE_KEYCHAIN:+"$NATIVE_KEYCHAIN"}
}

# MARK: - What to build

case $channel in
    stable) configuration=Release product="Native" channel_condition="" app_icon=AppIcon ;;
    beta) configuration=Release product="Native" channel_condition=NATIVE_BETA app_icon=AppIconBeta ;;
    nightly) configuration=Nightly product="Native Nightly" channel_condition=NATIVE_NIGHTLY app_icon=AppIconNightly ;;
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
custom_url_prefix=1
[ -n "$url_prefix" ] || { url_prefix="$releases/download/$tag/"; custom_url_prefix=0; }
# How many earlier archives each update gets a delta from (see Appcast).
delta_seeds=3
output=${output:-${RUNNER_TEMP:-${TMPDIR:-/tmp}}/native-release/$channel}
output=${output%/}
archive="$output/$asset_base.xcarchive"
app="$output/$product.app"
# Nightly archives carry the build number so a download in flight never meets a replaced file.
if [ "$channel" = nightly ]; then zip_name="$asset_base-$build_number.zip" dmg_name="$asset_base.dmg"; else zip_name="$asset_base-$version.zip" dmg_name="$asset_base-$version.dmg"; fi

# A rehearsal checks everything publishing needs, so it fails where the real run would.
if [ "$MODE" = publish ] || [ "$MODE" = rehearse ]; then
    [[ $repo == *PLACEHOLDER* ]] && die "set NATIVE_GITHUB_REPOSITORY in Config/Shared.xcconfig before publishing (docs/releasing.md)"
    [ -n "$public_key" ] || die "set NATIVE_SPARKLE_PUBLIC_KEY before publishing (docs/releasing.md, \"Repository secrets\")"
    [ -n "$key_file" ] || security find-generic-password -s https://sparkle-project.org -a ed25519 >/dev/null 2>&1 \
        || die "no Sparkle signing key: pass --ed-key-file or add it to the Keychain (docs/releasing.md, \"One-time setup\")"
    [ -z "$(git status --porcelain)" ] || die "the working tree has changes; release from a clean checkout"
    require_tool gh "brew install gh"
    [ -n "${SENTRY_AUTH_TOKEN:-}" ] || die "set SENTRY_AUTH_TOKEN before publishing (docs/releasing.md, Sentry crash symbols)"
    [ -n "${NATIVE_SENTRY_DSN:-}" ] || die "set NATIVE_SENTRY_DSN before publishing (docs/releasing.md, repository secrets)"
fi

# Developer ID for anything that leaves this Mac; ad hoc is fine for a local dry run.
if [ -z "$identity" ]; then
    if identities | grep -q "Developer ID Application"; then
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
    team=$(identities | sed -n "s/.*\"$identity.*(\([A-Z0-9]*\))\".*/\1/p" | head -1)
fi

log "$product $version (build $build_number) from ${sha:0:7}, $MODE"

# MARK: - Archive and sign

log "Archiving ($configuration)"
# A secure timestamp is what notarization wants; ad hoc signatures can't carry one. Ad hoc builds
# also go without the hardened runtime: its library validation won't load the ad hoc signed Sparkle
# framework into an ad hoc signed app. Developer ID builds share one team, so they keep it.
sign_flags="" runtime=()
if [ "$identity" = "-" ]; then
    runtime=(ENABLE_HARDENED_RUNTIME=NO)
else
    sign_flags="--timestamp${NATIVE_KEYCHAIN:+ --keychain $NATIVE_KEYCHAIN}"
fi
run rm -rf "$archive" "$app"
run mkdir -p "$output"
build_embedded
# arm64 only: macOS 27 doesn't run on Intel, and without this the packages (which still support macOS
# 15) also compile an x86_64 slice nothing links. The standalone host is built universal on its own.
run xcodebuild archive \
    -project native.xcodeproj -scheme native -configuration "$configuration" \
    -archivePath "$archive" -derivedDataPath "$output/DerivedData" -destination 'generic/platform=macOS' \
    MARKETING_VERSION="$version" CURRENT_PROJECT_VERSION="$build_number" \
    NATIVE_CHANNEL_CONDITION="$channel_condition" NATIVE_APP_ICON_NAME="$app_icon" \
    NATIVE_SENTRY_DSN="${NATIVE_SENTRY_DSN:-}" NATIVE_SPARKLE_PUBLIC_KEY="$public_key" \
    CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY="$identity" DEVELOPMENT_TEAM="$team" \
    CODE_SIGN_INJECT_BASE_ENTITLEMENTS=NO OTHER_CODE_SIGN_FLAGS="$sign_flags" ${runtime[@]+"${runtime[@]}"} \
    ARCHS=arm64 ${settings[@]+"${settings[@]}"} -quiet
run ditto "$archive/Products/Applications/$product.app" "$app"
# Xcode signs the Sparkle framework it embeds but leaves the helpers inside it ad hoc, as Sparkle ships
# them, and notarization refuses ad hoc code. Sign them inside out the way Sparkle's documentation
# says, then the framework and the app around them again.
if [ "$identity" != "-" ]; then
    sparkle="$app/Contents/Frameworks/Sparkle.framework"
    sign=(codesign --force --sign "$identity" --options runtime --timestamp ${keychain_args[@]+"${keychain_args[@]}"})
    run "${sign[@]}" "$sparkle/Versions/B/XPCServices/Installer.xpc"
    run "${sign[@]}" --preserve-metadata=entitlements "$sparkle/Versions/B/XPCServices/Downloader.xpc"
    run "${sign[@]}" "$sparkle/Versions/B/Autoupdate"
    run "${sign[@]}" "$sparkle/Versions/B/Updater.app"
    run "${sign[@]}" "$sparkle"
    run "${sign[@]}" --preserve-metadata=entitlements,requirements,flags "$app"
fi
run codesign --verify --deep --strict --verbose=2 "$app"

# MARK: - Notarize and staple

log "Notarizing"
run ditto -c -k --sequesterRsrc --keepParent "$app" "$output/notarize.zip"
notarize "$output/notarize.zip" "${notary_args[@]}"
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
    # The app carries LICENSE.md in its resources; the disk image shows it beside the app too.
    run cp LICENSE.md "$staging/LICENSE.md"
    run hdiutil create -quiet -volname "$product" -srcfolder "$staging" -ov -format ULFO "$output/$dmg_name"
    run rm -rf "$staging"
    [ "$identity" = "-" ] || run codesign --sign "$identity" --timestamp ${keychain_args[@]+"${keychain_args[@]}"} "$output/$dmg_name"
    notarize "$output/$dmg_name" "${notary_args[@]}"
    notary xcrun stapler staple "$output/$dmg_name"
fi

# What users download and install, against the budgets in docs/app-size.md; over budget stops here.
size_args=(--zip "$output/appcast/$zip_name")
[ "$make_dmg" = 1 ] && size_args+=(--dmg "$output/$dmg_name")
run "$ROOT/scripts/release/size-check.sh" "$app" "${size_args[@]}"

# MARK: - Appcast

log "Generating the appcast"
appcast="$output/appcast/appcast.xml"
feed="$releases/latest/download/appcast.xml"
[ "$channel" = nightly ] && feed="$releases/download/nightly/appcast.xml"
# Start from the published feed so earlier items (and the other channel's) stay in it.
if [ "$MODE" != plan ] && [[ $repo != *PLACEHOLDER* ]]; then
    curl -fsSL "$feed" -o "$appcast" 2>/dev/null || log "No published feed yet; starting a new one"
fi
sparkle_bin=${SPARKLE_BIN:-$output/DerivedData/SourcePackages/artifacts/sparkle/Sparkle/bin}
appcast_args=(--download-url-prefix "$url_prefix" --embed-release-notes --full-release-notes-url "$releases"
    --maximum-deltas "$delta_seeds")
[ "$channel" = beta ] && appcast_args+=(--channel beta)
[ "$channel" = nightly ] && appcast_args+=(--maximum-versions 1)
[ -n "$key_file" ] && appcast_args+=(--ed-key-file "$key_file")

# Replaces text in the appcast, literally.
replace_in_appcast() {
    local xml
    xml=$(<"$appcast")
    # Assigned first: inside double quotes, bash 3.2 would keep the replacement's quotes.
    xml=${xml//"$1"/"$2"}
    printf '%s\n' "$xml" >"$appcast"
}

# Sparkle makes a delta update from every earlier archive in the folder to this one: a few MB instead
# of the whole app. Seed it with the archives users are most likely to have: the last few v* releases'
# for stable and beta, or the ones the rolling nightly release still holds (it keeps two). Prints
# "<tag> <asset>" for each.
delta_seed_assets() {
    if [ "$channel" = nightly ]; then
        gh release view nightly --repo "$repo" --json assets --jq '.assets[].name' |
            grep -E "^$asset_base-[0-9]+\.zip$" | grep -vxF "$zip_name" | sort -t- -k3 -n | tail -n "$delta_seeds" |
            sed 's/^/nightly /'
    else
        gh release list --repo "$repo" --limit 30 --json tagName,isDraft --jq '.[] | select(.isDraft | not) | .tagName' |
            grep -E '^v[0-9]' | grep -vxF "$tag" | head -n "$delta_seeds" |
            while read -r seed_tag; do echo "$seed_tag $asset_base-${seed_tag#v}.zip"; done
    fi
}

# generate_keys keeps the private key in the login keychain under this service and account.
can_sign=1
if [ -z "$key_file" ] && [ "$MODE" = dry-run ] && ! security find-generic-password -s https://sparkle-project.org -a ed25519 >/dev/null 2>&1; then
    can_sign=0
fi

seeds=()
if [ "$can_sign" = 1 ] && [ "$MODE" != plan ] && [ "$custom_url_prefix" = 0 ] && [[ $repo != *PLACEHOLDER* ]]; then
    if ! command -v gh >/dev/null 2>&1; then
        warn "gh isn't installed, so this update has no deltas: every user downloads the whole app"
    else
        while read -r seed_tag seed_name; do
            [ -n "$seed_name" ] || continue
            if run gh release download "$seed_tag" --repo "$repo" --pattern "$seed_name" --dir "$output/appcast" --clobber; then
                seeds+=("$seed_name $releases/download/$seed_tag/$seed_name")
            else
                warn "couldn't download $seed_name from $seed_tag; no delta from it"
            fi
        done < <(delta_seed_assets 2>/dev/null || true)
        [ ${#seeds[@]} -gt 0 ] || log "No earlier releases to make deltas from"
    fi
fi

if [ "$can_sign" = 0 ]; then
    warn "no Sparkle signing key in the keychain (docs/releasing.md, \"One-time setup\"); not signing an appcast"
    printf '  [dry run] would run: %s\n' "$(quoted "$sparkle_bin/generate_appcast" "${appcast_args[@]}" "$output/appcast")" >&2
else
    run "$sparkle_bin/generate_appcast" "${appcast_args[@]}" "$output/appcast"
fi

deltas=()
if [ "$can_sign" = 1 ] && [ "$MODE" != plan ]; then
    # generate_appcast points every item whose archive is in the folder at this release; a seed that's
    # still in the feed keeps the URL it was published with.
    for seed in ${seeds[@]+"${seeds[@]}"}; do
        replace_in_appcast "url=\"$url_prefix${seed%% *}\"" "url=\"${seed#* }\""
    done
    # GitHub turns spaces in asset names into dots, so Native Nightly's deltas take a dash like its
    # archives do.
    for delta in "$output/appcast"/*.delta; do
        [ -e "$delta" ] || continue
        name=$(basename "$delta")
        if [[ $name == *" "* ]]; then
            run mv "$delta" "$output/appcast/${name// /-}"
            replace_in_appcast "/${name// /%20}\"" "/${name// /-}\""
        fi
        deltas+=("$output/appcast/${name// /-}")
    done
    [ ${#deltas[@]} = 0 ] || log "Made ${#deltas[@]} delta updates"
    # generate_appcast only warns when the app's SUPublicEDKey doesn't match the signing key, and then
    # leaves the archive unsigned, which no installed copy would accept.
    if [ -n "$public_key" ]; then
        signed=$(xmllint --xpath "count(//item/enclosure[contains(@url, '/$zip_name')][@*[local-name()='edSignature']])" "$appcast")
        [ "$signed" = 1 ] || die "the appcast has no EdDSA signature for $zip_name: is the signing key the one NATIVE_SPARKLE_PUBLIC_KEY belongs to?"
    fi
fi

# MARK: - Host

# The standalone native-host and its signed feed, for hosts that update themselves.
host_args=(--channel "$channel" --version "$version" --build-number "$build_number" --output "$output"
    --identity "$identity" --notes "$notes")
[ -n "$key_file" ] && host_args+=(--ed-key-file "$key_file")
[ -n "${NATIVE_LINUX_HOST_DIR:-}" ] && host_args+=(--linux "$NATIVE_LINUX_HOST_DIR")
case $MODE in plan) host_args+=(--plan) ;; notarize | rehearse | publish) host_args+=(--notarize) ;; esac
SPARKLE_BIN=$sparkle_bin "$ROOT/scripts/release/host.sh" "${host_args[@]}"
host_feed="host-feed.json"
[ "$channel" = beta ] && host_feed="host-feed-beta.json"
host_files=()
[ -f "$output/host/$host_feed" ] && host_files=("$output/host/$host_feed" "$output/host/$host_feed.sig")

# MARK: - Celebration icons

# One icon pack per celebration and the index that lists them, which the app downloads when someone
# chooses a celebration (docs/celebrations-artwork.md). The index is signed with the appcast's key,
# printed bare by `sign_update -p`; --disable-signing-warning keeps it from editing the file.
celebration_files=()
celebration_sign="$sparkle_bin/sign_update -p --disable-signing-warning"
if [ "$MODE" = plan ]; then
    printf '  [plan] would run: %s\n' "scripts/release/celebration-assets.sh pack $output/celebrations $version" >&2
elif [ "$key_file" = - ]; then
    warn "the Sparkle key came on stdin and is already read; not packing celebration icons"
elif [ -z "$key_file" ] && [ "$MODE" = dry-run ] && ! security find-generic-password -s https://sparkle-project.org -a ed25519 >/dev/null 2>&1; then
    warn "no Sparkle signing key in the keychain; not packing celebration icons"
else
    [ -n "$key_file" ] && celebration_sign+=" --ed-key-file $key_file"
    export CELEBRATION_ASSETS_SIGN=$celebration_sign
    run "$ROOT/scripts/release/celebration-assets.sh" pack "$output/celebrations" "$version"
    celebration_files=("$output/celebrations"/celebration-*.json "$output/celebrations/celebration-assets.json.sig")
fi

# MARK: - Symbols

# Symbols reach Sentry before users can receive this build: the app's dSYMs and the standalone host's.
# A rehearsal checks the token and finds the symbols but uploads nothing; dry runs print the upload.
symbols=("$archive/dSYMs" "$output/host-dSYMs")
case $MODE in
    publish) run bash "$ROOT/scripts/release/sentry.sh" "${symbols[@]}" ;;
    rehearse) run bash "$ROOT/scripts/release/sentry.sh" --no-upload "${symbols[@]}" ;;
    *) printf '  [dry run] would run: %s\n' "$(quoted bash "$ROOT/scripts/release/sentry.sh" "${symbols[@]}")" >&2 ;;
esac

# MARK: - Publish

log "Publishing to $repo"
assets=("$output/appcast/$zip_name" "$output/host/native-host-$build_number-macos-universal"
    ${deltas[@]+"${deltas[@]}"})
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
    remote gh release upload nightly --repo "$repo" --clobber "${assets[@]}" \
        ${celebration_files[@]+"${celebration_files[@]}"}
    remote gh release upload nightly --repo "$repo" --clobber "$output/appcast/appcast.xml" ${host_files[@]+"${host_files[@]}"}
    if [ "$MODE" = publish ]; then
        # Keep the newest two archives and hosts so downloads already in flight still finish (and the
        # next nightly has deltas from both), and only the deltas this appcast lists.
        names=$(gh release view nightly --repo "$repo" --json assets --jq '.assets[].name')
        current_deltas=" $(for delta in ${deltas[@]+"${deltas[@]}"}; do basename "$delta"; done | tr '\n' ' ')"
        # A listing can be empty (the first nightly has no deltas): `|| true` keeps pipefail from
        # stopping the release over a grep that matched nothing.
        { { grep -E "^$asset_base-[0-9]+\.zip$" <<<"$names" || true; } | sort -t- -k3 -n | keep_all_but_two
          { grep -E "^native-host-[0-9]+-" <<<"$names" || true; } | sort -t- -k3 -n | keep_all_but_two
          { grep -E '\.delta$' <<<"$names" || true; } | while read -r name; do
              [[ $current_deltas == *" $name "* ]] || echo "$name"
          done; } |
            while read -r old; do run gh release delete-asset nightly "$old" --repo "$repo" --yes; done
    fi
else
    prerelease=()
    [ "$channel" = beta ] && prerelease=(--prerelease)
    # A draft with every asset, then published at once: the feed never sees a half-made release.
    remote gh release create "$tag" --repo "$repo" --draft --verify-tag --title "Native $version" \
        ${prerelease[@]+"${prerelease[@]}"} "${notes_flag[@]}" "${assets[@]}" "$output/appcast/appcast.xml" \
        ${host_files[@]+"${host_files[@]}"} ${celebration_files[@]+"${celebration_files[@]}"}
    remote gh release edit "$tag" --repo "$repo" --draft=false
    if [ "$channel" = beta ]; then
        # Betas are prereleases, so releases/latest still points at the newest stable release.
        # The feed lives there, so it gets the appcast with this beta in it too.
        latest=""
        [ "$MODE" = publish ] && latest=$(gh api "repos/$repo/releases/latest" --jq .tag_name 2>/dev/null || true)
        if [ -n "$latest" ] || [ "$MODE" != publish ]; then
            remote gh release upload "${latest:-<latest stable tag>}" --repo "$repo" --clobber "$output/appcast/appcast.xml" \
                ${host_files[@]+"${host_files[@]}"}
        else
            warn "there's no stable release yet, so beta users can't receive this update until there is one"
        fi
    fi
fi

log "Done. Artifacts are in $output"
