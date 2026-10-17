#!/usr/bin/env bash
# Sets up, or tears down, signing on a CI runner: a throwaway keychain with the Developer ID
# certificate, a notarytool profile in it, and the Sparkle key in a private file.
#
#   scripts/release/ci-signing.sh setup     # reads the secrets below, writes $GITHUB_ENV
#   scripts/release/ci-signing.sh teardown
#
# Secrets (docs/releasing.md, "Repository secrets"): DEVELOPER_ID_CERTIFICATE_P12 (base64),
# DEVELOPER_ID_CERTIFICATE_PASSWORD, NOTARY_API_KEY_P8 (base64), NOTARY_API_KEY_ID,
# NOTARY_API_ISSUER_ID, SPARKLE_PRIVATE_KEY.
set -euo pipefail
source "$(dirname "$0")/lib.sh"

work=${RUNNER_TEMP:?ci-signing.sh runs on CI runners}/native-signing
keychain="$work/release.keychain-db"

case ${1-} in
    setup)
        for secret in DEVELOPER_ID_CERTIFICATE_P12 DEVELOPER_ID_CERTIFICATE_PASSWORD NOTARY_API_KEY_P8 \
            NOTARY_API_KEY_ID NOTARY_API_ISSUER_ID SPARKLE_PRIVATE_KEY; do
            [ -n "${!secret:-}" ] || die "the $secret secret is missing (docs/releasing.md, \"Repository secrets\")"
        done
        mkdir -p "$work"
        chmod 700 "$work"
        password=$(uuidgen)
        security create-keychain -p "$password" "$keychain"
        security set-keychain-settings -lut 21600 "$keychain"
        security unlock-keychain -p "$password" "$keychain"
        # Keep the login keychain searchable too, so system roots still resolve.
        # shellcheck disable=SC2046 # one keychain path per word is what list-keychains wants
        security list-keychains -d user -s "$keychain" $(security list-keychains -d user | tr -d '"')

        printf '%s' "$DEVELOPER_ID_CERTIFICATE_P12" | base64 --decode >"$work/certificate.p12"
        security import "$work/certificate.p12" -k "$keychain" -P "$DEVELOPER_ID_CERTIFICATE_PASSWORD" \
            -T /usr/bin/codesign -T /usr/bin/security
        security set-key-partition-list -S apple-tool:,apple:,codesign: -s -k "$password" "$keychain" >/dev/null
        rm -f "$work/certificate.p12"

        printf '%s' "$NOTARY_API_KEY_P8" | base64 --decode >"$work/notary.p8"
        xcrun notarytool store-credentials "${NATIVE_NOTARY_PROFILE:-native-notary}" --key "$work/notary.p8" \
            --key-id "$NOTARY_API_KEY_ID" --issuer "$NOTARY_API_ISSUER_ID" --keychain "$keychain" >/dev/null
        rm -f "$work/notary.p8"

        (umask 077 && printf '%s' "$SPARKLE_PRIVATE_KEY" >"$work/sparkle.key")
        {
            echo "NATIVE_KEYCHAIN=$keychain"
            echo "SPARKLE_KEY_FILE=$work/sparkle.key"
        } >>"${GITHUB_ENV:?}"
        log "Signing is ready"
        ;;
    teardown)
        security delete-keychain "$keychain" 2>/dev/null || true
        rm -rf "$work"
        ;;
    *) die "usage: ci-signing.sh setup|teardown" ;;
esac
