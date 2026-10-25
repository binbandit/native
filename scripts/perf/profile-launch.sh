#!/bin/bash
# Records a Time Profiler trace of an isolated instance's launch, from its first instructions,
# without `xctrace --launch` (which can start a different Native than the one asked for: never
# point it at a Native binary). Opens the instance's own build, stops the process at once,
# attaches the profiler, then lets it run.
#
#   scripts/perf/profile-launch.sh [--name NAME] [--fixture] [--seconds S] [--output PATH] [-- app arguments…]
#
# The instance must be built already (`scripts/dev/run-isolated.sh NAME --build`). `--fixture`
# seeds it like `just perf --fixture`. The trace is a few hundred MB: open it, read what you need,
# then delete it and the recording's `$TMPDIR/instruments*.ktrace`.
set -euo pipefail

name=perf
fixture=0
seconds=10
output=""
app_args=()
usage="usage: $0 [--name NAME] [--fixture] [--seconds S] [--output PATH] [-- app arguments…]"
while [ $# -gt 0 ]; do
    case "$1" in
        --name) name=$2; shift ;;
        --fixture) fixture=1 ;;
        --seconds) seconds=$2; shift ;;
        --output) output=$2; shift ;;
        --) shift; app_args=("$@"); break ;;
        *) echo "$usage" >&2; exit 2 ;;
    esac
    shift
done

root=$(git -C "$(dirname "$0")" rev-parse --show-toplevel)
run="$root/scripts/dev/run-isolated.sh"
app="/tmp/native-dd/$name/Build/Products/Debug/Native.app"
process="native-dd/$name/Build/Products/Debug/Native.app/Contents/MacOS/Native"
[ -n "$output" ] || output="/tmp/native-dd/$name-launch.trace"
bundle=$(/usr/libexec/PlistBuddy -c "Print :CFBundleIdentifier" "$app/Contents/Info.plist" 2>/dev/null) ||
    { echo "no build at $app; run $run $name --build first" >&2; exit 1; }
[[ $bundle == *".dev.$name" ]] || { echo "$app isn't $name's isolated build ($bundle)" >&2; exit 1; }

"$run" "$name" --quit >/dev/null
[ "$fixture" = 1 ] && "$root/scripts/perf/fixture.sh" "$bundle" "/private/tmp/native-perf/$name/fixture"
rm -rf "$output"
# The same arguments run-isolated.sh gives the instance.
open -n "$app" --args -defaultAgent claude-code -agentDefaults.claude-code.model haiku \
    -agentDefaults.claude-code.effort low -gitWorktreesFolder "$HOME/.native/worktrees-dev/$name" \
    ${app_args[@]+"${app_args[@]}"}
pid=""
for _ in $(seq 1 2000); do
    pid=$(pgrep -nf "$process" || true)
    [ -n "$pid" ] && break
done
[ -n "$pid" ] || { echo "Native didn't start" >&2; exit 1; }
kill -STOP "$pid"

log=$(mktemp)
trap 'kill -CONT "$pid" 2>/dev/null || true; rm -f "$log"' EXIT
# Always with a time limit, and never killed: a killed recording leaves its kernel trace growing.
xcrun xctrace record --template 'Time Profiler' --attach "$pid" --time-limit "${seconds}s" --output "$output" \
    >"$log" 2>&1 &
recording=$!
for _ in $(seq 1 600); do
    grep -q "Ctrl-C to stop" "$log" && break
    sleep 0.1
done
kill -CONT "$pid"
wait "$recording" || { cat "$log" >&2; exit 1; }
"$run" "$name" --quit >/dev/null
echo "trace $output"
echo "the launch milestones (LaunchMetrics) are Points of Interest in it"
