#!/bin/bash
# Builds and runs a copy of Native that shares nothing with other test instances, for checking a
# change in the running app while other agents do the same.
#
#   scripts/dev/run-isolated.sh <name> [--no-build] [-- app arguments…]
#   scripts/dev/run-isolated.sh <name> --build    # build only (compile checks), into the same folder
#   scripts/dev/run-isolated.sh <name> --quit     # quit this instance and stop its host and agents
#   scripts/dev/run-isolated.sh <name> --reset    # also forget its defaults, Application Support and host channel
#   scripts/dev/run-isolated.sh <name> --remove   # reset, then delete its build (about 6 GB); run when done
#
# The build goes to /tmp/native-dd/<name> with the bundle id suffixed `.dev.<name>`, so the instance
# gets its own defaults domain and its own Application Support folder, and its host its own launchd
# label and channel (docs/durability.md, "Development builds"): instances never share a host, a
# socket or a store. Its task worktrees go to ~/.native/worktrees-dev/<name> instead of the real
# ~/.native/worktrees. Codex runs `gpt-6.1-sol` unless the app arguments say otherwise. Prints the
# instance's pid, window id and host channel, for automation scoped to it.
set -euo pipefail

usage() {
    echo "usage: $0 <name> [--build | --no-build | --quit | --reset | --remove] [-- app arguments…]" >&2
    exit 2
}

[ $# -ge 1 ] || usage
name=$1
shift
[[ "$name" =~ ^[a-z0-9-]+$ ]] || { echo "name: lowercase letters, digits and dashes only" >&2; exit 2; }

action=run
build=1
app_args=()
while [ $# -gt 0 ]; do
    case "$1" in
        --quit) action=quit ;;
        --reset) action=reset ;;
        --remove) action=remove ;;
        --no-build) build=0 ;;
        --build) action=build ;;
        --) shift; app_args=("$@"); break ;;
        *) usage ;;
    esac
    shift
done

root=$(git -C "$(dirname "$0")" rev-parse --show-toplevel)
derived="/tmp/native-dd/$name"
app="$derived/Build/Products/Debug/Native.app"
# Matched without the leading /tmp, which macOS reports as /private/tmp.
process="native-dd/$name/Build/Products/Debug/Native.app/Contents/MacOS/Native"
# The instance's host binary, run by its launchd job or, as a fallback, by the app itself.
host_process="native-dd/$name/Build/Products/Debug/Native.app/Contents/Library/LoginItems/Native Host.app/Contents/MacOS/Native Host"
support="$HOME/Library/Application Support"
worktrees="$HOME/.native/worktrees-dev/$name"

# The built app's bundle id, only when it's this instance's own (suffixed `.dev.<name>`). A plain
# build into the same folder carries the shared development id, and --quit or --reset must never
# touch that domain's defaults, data or host.
bundle_id() {
    local id
    id=$(/usr/libexec/PlistBuddy -c "Print :CFBundleIdentifier" "$app/Contents/Info.plist" 2>/dev/null) || return 1
    if [[ $id != *".dev.$name" ]]; then
        echo "the app in $derived is not $name's isolated build (bundle id $id); leaving that id's data alone" >&2
        return 1
    fi
    printf '%s\n' "$id"
}

quit_app() {
    pkill -f "$process" 2>/dev/null || true
}

# The channel this build's host runs on (a hash of its build folder), empty if unknown.
host_channel() {
    /usr/libexec/PlistBuddy -c "Print :EnvironmentVariables:NATIVE_HOST_CHANNEL" \
        "$app/Contents/Library/LaunchAgents/NativeHost.plist" 2>/dev/null || true
}

quit() {
    quit_app
    local id
    id=$(bundle_id 2>/dev/null) || return 0
    # The instance's development host: its launchd job, then any copy the app started itself
    # (which exits with the app anyway, given a moment).
    for label in $(launchctl list | awk '{print $3}' | grep -F "$id.host." || true); do
        launchctl bootout "gui/$(id -u)/$label" 2>/dev/null || true
    done
    pkill -f "$host_process" 2>/dev/null || true
}

case "$action" in
quit)
    quit
    echo "quit $name"
    exit 0
    ;;
reset | remove)
    quit
    if id=$(bundle_id); then
        defaults delete "$id" 2>/dev/null || true
        rm -rf "$support/$id"
        channel=$(host_channel)
        [ -n "$channel" ] && rm -rf "$support/Native/Channels/$channel"
        rm -rf "$worktrees"
        echo "reset $name ($id)"
    else
        echo "nothing reset for $name" >&2
    fi
    if [ "$action" = remove ]; then
        rm -rf "$derived"
        echo "removed $derived"
    fi
    exit 0
    ;;
esac

if [ "$build" = 1 ]; then
    # Incremental, so an unchanged tree reuses the last build. Package versions come from Package.resolved
    # without asking the remotes, so a build works offline and doesn't wait on the network.
    log="$derived/build.log"
    mkdir -p "$derived"
    if ! xcodebuild -project "$root/native.xcodeproj" -scheme native -configuration Debug -skipPackageUpdates \
        -derivedDataPath "$derived" NATIVE_BUNDLE_IDENTIFIER_SUFFIX=".dev.$name" build >"$log" 2>&1; then
        grep -E "^/.*error:" "$log" | sort -u | head -20 >&2
        echo "build failed; full log: $log" >&2
        exit 1
    fi
fi
if [ "$action" = build ]; then
    echo "built $name"
    exit 0
fi
[ -d "$app" ] || { echo "no build at $app; run without --no-build" >&2; exit 1; }
bundle_id >/dev/null || { echo "run without --no-build to rebuild it as $name" >&2; exit 1; }

# Relaunching replaces the app but leaves its background host running, so durability and host
# handoffs can be tested by relaunching; --quit and --reset stop the host too.
quit_app
defaults_args=()
[[ " ${app_args[*]-} " == *" -agentDefaults.codex.model "* ]] || defaults_args=(-agentDefaults.codex.model gpt-6.1-sol)
[[ " ${app_args[*]-} " == *" -gitWorktreesFolder "* ]] || defaults_args+=(-gitWorktreesFolder "$worktrees")
open -n "$app" --args ${defaults_args[@]+"${defaults_args[@]}"} ${app_args[@]+"${app_args[@]}"}

pid=""
for _ in $(seq 1 50); do
    pid=$(pgrep -nf "$process" || true)
    [ -n "$pid" ] && break
    sleep 0.2
done
[ -n "$pid" ] || { echo "Native didn't start" >&2; exit 1; }

# The first normal-level window the instance shows.
window=$(swift -e '
import CoreGraphics
import Foundation
let pid = Int(CommandLine.arguments[1])!
for _ in 0..<100 {
    let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] ?? []
    if let window = windows.first(where: { $0[kCGWindowOwnerPID as String] as? Int == pid && $0[kCGWindowLayer as String] as? Int == 0 }) {
        print(window[kCGWindowNumber as String]!)
        exit(0)
    }
    usleep(200_000)
}
' "$pid" 2>/dev/null || true)

echo "name $name"
echo "bundle $(bundle_id)"
echo "pid $pid"
echo "window ${window:-unknown}"
echo "host channel $(host_channel)"
