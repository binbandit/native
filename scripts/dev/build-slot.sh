#!/bin/bash
# Runs xcodebuild at a lower priority and at most four at a time on this Mac, so whoever is using it
# keeps a responsive machine while agents build. Builds past the limit wait their turn.
#
#   scripts/dev/build-slot.sh <xcodebuild arguments…>
#
# Without -jobs, the running builds share the cores (at least 4 each). NATIVE_BUILD_SLOTS changes the limit.
set -euo pipefail

slots=/tmp/native-build-slots
limit=${NATIVE_BUILD_SLOTS:-4}
mkdir -p "$slots"

slot=""
waiting=0
while [ -z "$slot" ]; do
    for i in $(seq 1 "$limit"); do
        if mkdir "$slots/$i" 2>/dev/null; then
            echo $$ >"$slots/$i/pid"
            slot="$slots/$i"
            break
        fi
        # A slot whose build ended without freeing it is free again.
        owner=$(cat "$slots/$i/pid" 2>/dev/null || true)
        if [ -n "$owner" ] && ! kill -0 "$owner" 2>/dev/null; then
            rm -rf "${slots:?}/$i"
        fi
    done
    if [ -z "$slot" ]; then
        [ "$waiting" = 1 ] || echo "waiting for a build slot ($limit builds running)" >&2
        waiting=1
        sleep 5
    fi
done
trap 'rm -rf "$slot"' EXIT

arguments=("$@")
if [[ " $* " != *" -jobs "* ]]; then
    cores=$(sysctl -n hw.ncpu)
    running=$(find "$slots" -mindepth 1 -maxdepth 1 -type d | wc -l | tr -d ' ')
    jobs=$((cores / running))
    [ "$jobs" -ge 4 ] || jobs=4
    arguments+=(-jobs "$jobs")
fi
nice -n 10 taskpolicy -c utility xcodebuild "${arguments[@]}"
