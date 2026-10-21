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

# Waiting builds take a ticket and get slots in the order they arrived, not whichever polls first.
# A ticket is named by arrival time and pid; a build that dies leaves a ticket nobody waits on, which
# the others drop.
queue="$slots/queue"
mkdir -p "$queue"
ticket="$queue/$(date +%s)-$$"
touch "$ticket"
slot=""
# Counting the free slots and the tickets ahead, then claiming a slot, happens under one lock, so no
# build can claim a slot between another's count and its claim. Keep the lock file in place: deleting
# it could give waiters different inodes to lock. The kernel releases the lock when fd 9 closes,
# including when a holder dies, so recovery never removes another build's live lock.
lock="$slots/admit.flock"
trap 'rm -f "$ticket"; [ -z "$slot" ] || rm -rf "$slot"' EXIT

position=""
while [ -z "$slot" ]; do
    exec 9>"$lock"
    lockf 9
    busy=0
    for i in $(seq 1 "$limit"); do
        # A slot whose build ended without freeing it is free again.
        owner=$(cat "$slots/$i/pid" 2>/dev/null || true)
        if [ -n "$owner" ] && ! kill -0 "$owner" 2>/dev/null; then
            rm -rf "${slots:?}/$i"
        fi
        [ ! -d "$slots/$i" ] || busy=$((busy + 1))
    done
    for waiting in "$queue"/*; do
        kill -0 "${waiting##*-}" 2>/dev/null || rm -f "$waiting"
    done
    ahead=$(find "$queue" -type f | sort | awk -v me="$ticket" '$0 == me { exit } { n++ } END { print n + 0 }')
    if [ "$ahead" -lt $((limit - busy)) ]; then
        for i in $(seq 1 "$limit"); do
            if mkdir "$slots/$i" 2>/dev/null; then
                echo $$ >"$slots/$i/pid"
                slot="$slots/$i"
                rm -f "$ticket"
                break
            fi
        done
    fi
    exec 9>&-
    if [ -z "$slot" ]; then
        if [ "$ahead" != "$position" ]; then
            echo "waiting for a build slot: $limit builds running, $ahead ahead of this one" >&2
            position=$ahead
        fi
        sleep 5
    fi
done
rm -f "$ticket"

# A build takes several GB. With the disk nearly full, wait for space rather than fill it: a full disk
# breaks every app on the Mac, not just this build. Checked once the slot is ours, since the builds
# running while this one queued may have used the space; holding the slot meanwhile keeps the next
# build from starting too. NATIVE_BUILD_MIN_FREE_GB changes the floor.
floor=${NATIVE_BUILD_MIN_FREE_GB:-20}
announced=0
while [ "$(df -g /tmp | awk 'NR==2 {print $4}')" -lt "$floor" ]; do
    [ "$announced" = 1 ] || echo "waiting for disk space (under ${floor} GB free)" >&2
    announced=1
    sleep 30
done

arguments=("$@")
if [[ " $* " != *" -jobs "* ]]; then
    cores=$(sysctl -n hw.ncpu)
    running=$(find "$slots" -mindepth 1 -maxdepth 1 -type d -name '[0-9]*' | wc -l | tr -d ' ')
    jobs=$((cores / running))
    [ "$jobs" -ge 4 ] || jobs=4
    arguments+=(-jobs "$jobs")
fi
nice -n 10 taskpolicy -c utility xcodebuild "${arguments[@]}"
