#!/bin/bash
# Fails when an xcodebuild log has warnings from this repository's own files (the app, Packages/ and
# the project), so a new one is fixed in the change that adds it instead of piling up. Warnings from
# the SDK, remote packages and build tools are listed but don't fail: they aren't ours to fix.
#
#   scripts/check-warnings.sh <xcodebuild log>   # e.g. /tmp/native-dd/<name>/build.log
#
# Works on full and -quiet logs alike. CI runs it after every app build (.github/workflows).
set -euo pipefail

[ $# -eq 1 ] || { echo "usage: $0 <xcodebuild log>" >&2; exit 2; }
log=$1
root=$(git -C "$(dirname "$0")" rev-parse --show-toplevel)

# A diagnostic starts its line; the source excerpt the compiler prints under it is indented.
warnings=$(grep -E '^[^[:space:]|].*warning: ' "$log" | sort -u || true)
# Compared without case: macOS paths are case-insensitive, so a log can spell the checkout differently.
ours=$(awk -v root="$root/" 'index(tolower($0), tolower(root)) == 1' <<<"$warnings")
others=$(awk -v root="$root/" 'NF && index(tolower($0), tolower(root)) != 1' <<<"$warnings")

if [ -n "$others" ]; then
    echo "Warnings from outside this repository (not failing the build):"
    awk '{ print "  " $0 }' <<<"$others"
fi
if [ -z "$ours" ]; then
    echo "No warnings from this repository's files."
    exit 0
fi
echo "error: $(wc -l <<<"$ours" | tr -d ' ') warning(s) from this repository's files. Fix them; the build stays at zero:" >&2
awk '{ print "  " $0 }' <<<"$ours" >&2
if [ "${GITHUB_ACTIONS:-}" = true ]; then
    # Annotations, so each one shows on the pull request's diff.
    sed -nE "s#^$root/([^:]+):([0-9]+):([0-9]+): warning: (.*)#::error file=\1,line=\2,col=\3::\4#p" <<<"$ours"
fi
exit 1
