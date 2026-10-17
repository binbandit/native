#!/usr/bin/env bash
# Drafts release notes in Markdown from the conventional commits between two refs:
#   scripts/release/release-notes.sh <from-ref|""> [<to-ref>]
# An empty <from-ref> takes the whole history. Only user-facing types make the notes (feat, fix,
# perf, and anything marked breaking); chores, docs, tests, refactors and quicksaves are left out.
# The notes are generated, never hand-edited (docs/releasing.md, "Release notes").
set -euo pipefail

from=${1-}
to=${2:-HEAD}
range=$to
[ -n "$from" ] && range="$from..$to"
git rev-parse --verify --quiet "$to^{commit}" >/dev/null || { echo "release-notes: unknown ref $to" >&2; exit 1; }
[ -z "$from" ] || git rev-parse --verify --quiet "$from^{commit}" >/dev/null || { echo "release-notes: unknown ref $from" >&2; exit 1; }

breaking="" features="" fixes="" performance=""
pattern='^([a-z]+)(\(([^)]*)\))?(!)?: (.+)$'

while IFS= read -r -d '' record; do
    subject=${record%%$'\x1f'*}
    body=${record#*$'\x1f'}
    [[ $subject =~ $pattern ]] || continue
    type=${BASH_REMATCH[1]}
    scope=${BASH_REMATCH[3]}
    bang=${BASH_REMATCH[4]}
    description=${BASH_REMATCH[5]}
    line="- ${scope:+**$scope:** }$description"
    if [ -n "$bang" ] || [[ $body == *"BREAKING CHANGE:"* ]]; then
        breaking+="$line"$'\n'
        continue
    fi
    case $type in
        feat) features+="$line"$'\n' ;;
        fix) fixes+="$line"$'\n' ;;
        perf) performance+="$line"$'\n' ;;
    esac
done < <(git log --no-merges -z --format='%s%x1f%b' "$range")

section() {
    [ -n "$2" ] && printf '## %s\n%s\n' "$1" "$2"
    return 0
}

notes=$(section "Breaking changes" "$breaking"; section "New" "$features"; section "Fixes" "$fixes"; section "Performance" "$performance")
if [ -z "$notes" ]; then
    echo "Small improvements and fixes under the hood."
else
    printf '%s\n' "$notes"
fi
