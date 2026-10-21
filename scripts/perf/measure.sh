#!/bin/bash
# Measures Native's launch time, idle cost and child processes in its own isolated instance
# (`just perf`), for the numbers and budgets in docs/performance.md. Never touches another Native.
#
#   scripts/perf/measure.sh [--name NAME] [--no-build] [--launches N] [--seconds S] [--settle S] [--sessions N] [--fixture] [--launch-only] [-- app arguments…]
#
# Launch times come from the app's own `launch <milestone> <ms> ms` log lines (LaunchMetrics), from
# the moment the kernel started the process. Idle numbers are kernel counters for the app alone and
# for the app with every process under it, sampled over S seconds: with the window visible,
# minimized, and the app hidden. `--sessions N` first opens N Codex sessions that each answer one
# short prompt. The instance (`perf` unless --name gives another, so agents measuring at once don't
# quit each other's runs) works in a scratch project with Codex as its default agent, and is quit at
# the end. `--fixture` launches into a workspace like a real one instead: four projects, three with
# icons of their own (an SVG favicon, an SVG logo, an app icon in an asset catalog), and 30 tasks.
# `--launch-only` stops after the launches.
set -euo pipefail

name=perf
build=1
launches=5
seconds=30
settle=20
sessions=0
fixture=0
launch_only=0
app_args=()
usage="usage: $0 [--name NAME] [--no-build] [--launches N] [--seconds S] [--settle S] [--sessions N] [--fixture] [--launch-only] [-- app arguments…]"
while [ $# -gt 0 ]; do
    case "$1" in
        --name) name=$2; shift ;;
        --no-build) build=0 ;;
        --launches) launches=$2; shift ;;
        --seconds) seconds=$2; shift ;;
        --settle) settle=$2; shift ;;
        --sessions) sessions=$2; shift ;;
        --fixture) fixture=1 ;;
        --launch-only) launch_only=1 ;;
        --) shift; app_args=("$@"); break ;;
        *) echo "$usage" >&2; exit 2 ;;
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

# A scratch project and Codex as the default agent, once the instance has been built; it keeps them.
seed() {
    local plist="/tmp/native-dd/$name/Build/Products/Debug/Native.app/Contents/Info.plist" bundle
    local project=/tmp/native-perf/$name
    mkdir -p "$project"
    [ -f "$project/README.md" ] || printf '# Scratch project\n\nA throwaway folder for measuring Native.\n' >"$project/README.md"
    bundle=$(/usr/libexec/PlistBuddy -c "Print :CFBundleIdentifier" "$plist" 2>/dev/null) || return 0
    if [ "$fixture" = 1 ]; then
        "$root/scripts/perf/fixture.sh" "$bundle" "/private/tmp/native-perf/$name/fixture"
        return 0
    fi
    defaults read "$bundle" projects >/dev/null 2>&1 && return 0
    defaults write "$bundle" workspace "$project"
    defaults write "$bundle" defaultAgent codex
}

seed

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

# With the fixture, the window opens at its default size rather than as the last launch left it
# (macOS keeps that outside the app's own files), so every launch lays out the same rows.
[ "$fixture" = 1 ] && app_args=(-ApplePersistenceIgnoreState YES ${app_args[@]+"${app_args[@]}"})

launch() {
    "$run" "$name" "$@" -- ${app_args[@]+"${app_args[@]}"} | awk '/^pid / { print $2 }'
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
printf "%-6s %8s %10s %18s %11s %14s %17s %15s\n" run appInit firstFrame sidebarInteractive agentsReady \
    "main cpu@frame" "process cpu@frame" "main Minstr@frame"
[ "$build" = 1 ] && "$run" "$name" --build >/dev/null
for ((i = 1; i <= launches; i++)); do
    # Quit first, so the fixture's tasks aren't saved over as the last launch quits.
    "$run" "$name" --quit >/dev/null 2>&1 || true
    seed
    log=$(mktemp)
    /usr/bin/log stream --style compact --predicate 'subsystem == "Native" AND category == "Launch"' >"$log" 2>/dev/null &
    stream=$!
    sleep 1
    pid=$(launch --no-build)
    # Compact lines read `… Native[<pid>:<thread>] [Native:Launch] launch firstFrame 212 ms, main …`.
    value() { grep -F "Native[$pid:" "$log" | grep -oE "launch $1 [0-9]+" | awk '{ print $3 }' | head -1; }
    for _ in $(seq 1 150); do
        [ -n "$(value agentsReady)" ] && break
        sleep 0.2
    done
    kill "$stream" 2>/dev/null || true
    wait "$stream" 2>/dev/null || true
    label=$([ "$i" = 1 ] && [ "$build" = 1 ] && echo cold || echo "warm$i")
    cpu() { grep -F "Native[$pid:" "$log" | grep -oE "launch firstFrame .* $1 [0-9]+ ms cpu" | grep -oE "$1 [0-9]+" | awk '{ print $2 }'; }
    # Instructions the main thread ran: the same work costs the same count on any core.
    instructions() { grep -F "Native[$pid:" "$log" | grep -oE "launch firstFrame .* [0-9]+ M instructions on main" | grep -oE "[0-9]+ M instructions" | awk '{ print $1 }'; }
    printf "%-6s %8s %10s %18s %11s %14s %17s %15s\n" "$label" "$(value appInit)" "$(value firstFrame)" \
        "$(value sidebarInteractive)" "$(value agentsReady)" "$(cpu main)" "$(cpu process)" "$(instructions)"
    rm -f "$log"
done

[ "$launch_only" = 1 ] && exit 0

# Tasks, each answering one prompt; `Task › Stop` is enabled while a turn runs.
for ((i = 1; i <= sessions; i++)); do
    "$tools/drive" "$pid" menu File "New Task"
    sleep 3
    "$tools/drive" "$pid" prompt "Reply with the single word OK. Don't run any tools."
    sleep 2
    for _ in $(seq 1 120); do
        [ "$("$tools/drive" "$pid" enabled Task Stop)" = false ] && break
        sleep 1
    done
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
