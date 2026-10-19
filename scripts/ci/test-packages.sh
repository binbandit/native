#!/bin/bash
# Runs the Swift packages' tests the way CI does: every Packages/*/ with a Tests folder, so a new
# package is tested without anyone listing it, dealt into shards by how long each one's tests took on
# CI (scripts/ci/package-test-times.txt; a package not listed there counts as 30 seconds).
#
#   scripts/ci/test-packages.sh <shard> <shards>   # run shard <shard> of <shards>, counting from 1
#   scripts/ci/test-packages.sh --plan <shards>    # print each shard's packages and expected seconds
#
# Each package's output is a log group, followed by "<package> passed in <n>s"; a failing package is
# annotated with its name, the rest still run, and the run fails at the end.
set -euo pipefail

root=$(git -C "$(dirname "$0")" rev-parse --show-toplevel)
times="$root/scripts/ci/package-test-times.txt"
default_seconds=30

usage() {
    sed -n '2,10p' "$0" | sed 's/^# \{0,1\}//' >&2
    exit 2
}

# Prints "<shard> <seconds> <package>" for every tested package. Longest first, each to the shard
# with the least time so far (ties to the lower shard), so the shards finish close together.
assign() {
    local shards=$1 package
    for package in "$root"/Packages/*/Tests; do
        package=$(basename "$(dirname "$package")")
        awk -v p="$package" -v d="$default_seconds" '$1 == p { print $2, p; found = 1 } END { if (!found) print d, p }' \
            "$times"
    done | sort -k1,1nr -k2,2 |
        awk -v n="$shards" '{
            best = 1
            for (s = 2; s <= n; s++) if (load[s] < load[best]) best = s
            load[best] += $1
            print best, $1, $2
        }'
}

case ${1-} in
    --plan)
        [ $# -eq 2 ] || usage
        assign "$2" | awk '{ load[$1] += $2; names[$1] = names[$1] " " $3 }
            END { for (s in load) printf "shard %s: %ss:%s\n", s, load[s], names[s] }' | sort
        exit 0
        ;;
    '' | -*) usage ;;
esac
[ $# -eq 2 ] || usage
shard=$1 shards=$2

failed=""
for package in $(assign "$shards" | awk -v s="$shard" '$1 == s { print $3 }'); do
    echo "::group::$package"
    started=$SECONDS
    # The script runtime's Swift tests drive the real helper.
    if [ "$package" = ScriptRuntime ]; then "$root/scripts/build-script-runtime.sh"; fi
    if (cd "$root/Packages/$package" && swift test); then
        echo "::endgroup::"
        echo "$package passed in $((SECONDS - started))s"
    else
        echo "::endgroup::"
        echo "::error title=$package::swift test failed in Packages/$package"
        failed="$failed $package"
    fi
done
if [ -n "$failed" ]; then
    echo "Failed:$failed"
    exit 1
fi
