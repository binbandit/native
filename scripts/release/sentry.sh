#!/usr/bin/env bash
# Upload only release dSYMs, never a source bundle. The token stays in the environment.
# Usage: scripts/release/sentry.sh <archive/dSYMs> [--no-upload]
set -euo pipefail

symbols=${1:?Pass the archive dSYMs directory}
mode=${2:-}
[[ -z "$mode" || "$mode" = --no-upload ]] || { echo "Unknown option: $mode" >&2; exit 2; }
[[ -d "$symbols" ]] || { echo "Sentry: dSYMs directory is missing: $symbols" >&2; exit 1; }
if [[ -z "${SENTRY_AUTH_TOKEN:-}" ]]; then
    echo "Sentry: set SENTRY_AUTH_TOKEN to the release-upload token (also required for --no-upload)." >&2
    exit 1
fi

cli=${SENTRY_CLI:-}
if [[ -z "$cli" ]]; then
    work=$(mktemp -d "${TMPDIR:-/tmp}/native-sentry.XXXXXX")
    trap 'rm -rf "$work"' EXIT
    cli="$work/sentry-cli"
    curl --fail --silent --show-error --location \
        https://github.com/getsentry/sentry-cli/releases/download/3.8.0/sentry-cli-Darwin-universal \
        --output "$cli"
    echo "2c26914636c47ab9bf9e710484ad7b44d371cbec8bd29cafb36b3cf877bf4285  $cli" | shasum -a 256 --check --status
    chmod 700 "$cli"
fi

args=(debug-files upload --org "${SENTRY_ORG:-foxycorps}" --project "${SENTRY_PROJECT:-native}"
    --type dsym --no-sources --wait)
[[ -z "$mode" ]] || args+=("$mode")
"$cli" "${args[@]}" "$symbols"
