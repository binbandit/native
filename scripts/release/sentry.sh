#!/usr/bin/env bash
# Upload only release dSYMs, never a source bundle. The token stays in the environment.
# Usage: scripts/release/sentry.sh [--no-upload] <dSYMs folder>...
#   --no-upload finds the symbols and checks the token and project without uploading anything.
set -euo pipefail

mode="" folders=()
for arg in "$@"; do
    case $arg in
        --no-upload) mode=$arg ;;
        -*) echo "Unknown option: $arg" >&2; exit 2 ;;
        *) folders+=("$arg") ;;
    esac
done
[[ ${#folders[@]} -gt 0 ]] || { echo "Pass the dSYMs folders, e.g. the archive's dSYMs" >&2; exit 2; }
for folder in "${folders[@]}"; do
    [[ -d "$folder" ]] || { echo "Sentry: dSYMs folder is missing: $folder" >&2; exit 1; }
done
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
"$cli" "${args[@]}" "${folders[@]}"
