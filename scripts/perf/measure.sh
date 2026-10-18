#!/bin/bash
# Measures Native's launch time, idle cost and child processes in its own isolated instance
# (`just perf`), for the numbers and budgets in docs/performance.md. Never touches another Native.
#
#   scripts/perf/measure.sh [--no-build] [--launches N] [--seconds S] [--settle S]
#
# Launch times come from the app's own `launch <milestone> <ms> ms` log lines (LaunchMetrics), from
# the moment the kernel started the process. Idle numbers are kernel counters for the app alone and
# for the app with every process under it, sampled over S seconds: with the window visible,
# minimized, and the app hidden. The instance is quit at the end.
set -euo pipefail

name=perf
build=1
launches=5
seconds=30
settle=20
while [ $# -gt 0 ]; do
    case "$1" in
        --no-build) build=0 ;;
        --launches) launches=$2; shift ;;
        --seconds) seconds=$2; shift ;;
        --settle) settle=$2; shift ;;
        *) echo "usage: $0 [--no-build] [--launches N] [--seconds S] [--settle S]" >&2; exit 2 ;;
    esac
    shift
done

root=$(git -C "$(dirname "$0")" rev-parse --show-toplevel)
run="$root/scripts/dev/run-isolated.sh"
tools=/tmp/native-dd/perf-tools
mkdir -p "$tools"

# The sampling and driving tools, compiled once per change.
for tool in rusage drive; do
    if [ ! -x "$tools/$tool" ] || [ "$root/scripts/perf/$tool.swift" -nt "$tools/$tool" ]; then
        swiftc -O "$root/scripts/perf/$tool.swift" -o "$tools/$tool" 2>/dev/null
    fi
done

trap '"$run" "$name" --quit >/dev/null 2>&1 || true' EXIT

# Every process under `pid`, itself included.
tree() {
    local pids=$1 next=$1 children
    while [ -n "$next" ]; do
        children=$(for p in $next; do pgrep -P "$p" || true; done | tr '\n' ' ')
        pids="$pids $children"
        next=$children
    done
    echo "$pids" | tr -s ' ' ',' | sed 's/^,//; s/,$//'
}

launch() {
    "$run" "$name" "$@" | awk '/^pid / { print $2 }'
}

sample() {
    local label=$1 pid=$2
    echo "== $label"
    "$tools/rusage" "$seconds" "app=$pid" "with-children=$(tree "$pid")" | column -t
}

processes() {
    local pid=$1
    echo "== processes under Native"
    # shellcheck disable=SC2046
    ps -o pid=,ppid=,rss=,command= -p $(tree "$pid" | tr ',' ' ') |
        awk '{ rss = $3; $1 = $2 = $3 = ""; sub(/^ +/, ""); printf "%7.1f MB  %s\n", rss / 1024, substr($0, 1, 110) }'
}

# Launch: the first launch after a build is the coldest this can get without sudo (no `purge`);
# the rest are warm.
echo "== launch (ms from process start)"
printf "%-6s %8s %8s %18s %11s\n" run appInit firstFrame sidebarInteractive agentsReady
for i in $(seq 1 "$launches"); do
    log=$(mktemp)
    log stream --style compact --predicate 'subsystem == "Native" AND category == "Launch"' >"$log" 2>/dev/null &
    stream=$!
    sleep 1
    if [ "$i" = 1 ] && [ "$build" = 1 ]; then pid=$(launch); else pid=$(launch --no-build); fi
    for _ in $(seq 1 100); do
        grep -q "\[$pid:\?.*launch agentsReady\|Native\[$pid.*launch agentsReady" "$log" && break
        grep -E "Native\[$pid" "$log" | grep -q agentsReady && break
        sleep 0.2
    done
    kill "$stream" 2>/dev/null || true
    value() { grep -E "Native\[$pid" "$log" | grep -oE "launch $1 [0-9]+" | awk '{ print $3 }' | head -1; }
    label=$([ "$i" = 1 ] && [ "$build" = 1 ] && echo cold || echo "warm$i")
    printf "%-6s %8s %8s %18s %11s\n" "$label" "$(value appInit)" "$(value firstFrame)" \
        "$(value sidebarInteractive)" "$(value agentsReady)"
    rm -f "$log"
done

# Idle: the last launch stays up, left alone while agents start and list their sessions.
sleep "$settle"
sample "idle, window visible" "$pid"
processes "$pid"
echo "== memory (vmmap)"
vmmap --summary "$pid" 2>/dev/null | grep -E "^Physical footprint|^TOTAL" || true
"$tools/drive" "$pid" minimize
sleep 5
sample "idle, window minimized" "$pid"
"$tools/drive" "$pid" hide
sleep 5
sample "idle, app hidden" "$pid"
