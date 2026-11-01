#!/usr/bin/env bash
# Repack an unchanged public app and prove its embedded update key accepts production signatures.
# CI supplies the existing signing secret; nothing is published or installed.
set -euo pipefail
source "$(dirname "$0")/lib.sh"

: "${SPARKLE_PRIVATE_KEY:?CI must supply the production Sparkle signing key}"
: "${RUNNER_TEMP:?Run this rehearsal in CI}"
: "${GITHUB_REPOSITORY:?CI must supply the repository}"

scratch=$(mktemp -d "$RUNNER_TEMP/archive-signing.XXXXXX")
trap 'rm -rf "$scratch"' EXIT
original_tag=v0.2.0-beta.14
original_zip=Native-0.2.0-beta.14.zip
archive="$scratch/Native-0.2.0-beta.14.tar.xz"

# Use the project's pinned Sparkle tools, without compiling or launching an app.
"$ROOT/scripts/dev/build-slot.sh" -resolvePackageDependencies -project "$ROOT/native.xcodeproj" \
    -scheme native -clonedSourcePackagesDirPath "$scratch/SourcePackages" \
    -disableAutomaticPackageResolution -quiet
sparkle_bin="$scratch/SourcePackages/artifacts/sparkle/Sparkle/bin"

gh release download "$original_tag" --repo "$GITHUB_REPOSITORY" --pattern "$original_zip" --dir "$scratch"
mkdir "$scratch/original" "$scratch/unpacked"
ditto -x -k "$scratch/$original_zip" "$scratch/original"
app="$scratch/original/Native.app"
codesign --verify --deep --strict "$app"
xcrun stapler validate "$app"
pack_update_archive "$app" "$archive"
/usr/bin/tar -x -f "$archive" -C "$scratch/unpacked"
diff -qr "$app" "$scratch/unpacked/Native.app"
codesign --verify --deep --strict "$scratch/unpacked/Native.app"
xcrun stapler validate "$scratch/unpacked/Native.app"

# The secret travels only over stdin. Verification below uses only the unchanged app's public key.
signature=$(printf '%s' "$SPARKLE_PRIVATE_KEY" | "$sparkle_bin/sign_update" --ed-key-file - -p "$archive")
unset SPARKLE_PRIVATE_KEY
swift "$ROOT/scripts/release/verify-update-signature.swift" "$archive" "$signature" "$app/Contents/Info.plist"
printf 'Production archive signing verified for unchanged %s (%s bytes).\n' \
    "$original_tag" "$(stat -f %z "$archive")"
if [ -n "${GITHUB_STEP_SUMMARY:-}" ]; then
    # shellcheck disable=SC2016 # Markdown code spans are literal.
    printf 'Production key signed the repacked `%s` app. Its unchanged `SUPublicEDKey` accepted the `.tar.xz`; a tampered archive was rejected. No release, beta, tag or app was published or launched.\n' \
        "$original_tag" >> "$GITHUB_STEP_SUMMARY"
fi
