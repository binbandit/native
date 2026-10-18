#!/bin/bash
# Builds and runs a copy of Native that shares nothing with other test instances, for checking a
# change in the running app while other agents do the same.
#
#   scripts/dev/run-isolated.sh <name> [--no-build] [-- app arguments…]
#   scripts/dev/run-isolated.sh <name> --quit     # quit this instance and its host
#   scripts/dev/run-isolated.sh <name> --reset    # also forget its defaults and Application Support
#
# The build goes to /tmp/native-dd/<name> with the bundle id suffixed `.dev.<name>`, so the instance
# gets its own defaults domain and its own Application Support folder, and its host its own launchd
# label and channel (docs/durability.md, "Development builds"). Codex runs `gpt-6.1-sol` unless the
# app arguments say otherwise. Prints the instance's pid and window id, for automation scoped to it.
set -euo pipefail

usage() {
    echo "usage: $0 <name> [--no-build | --quit | --reset] [-- app arguments…]" >&2
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
        --no-build) build=0 ;;
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
support="$HOME/Library/Application Support"

bundle_id() {
    /usr/libexec/PlistBuddy -c "Print :CFBundleIdentifier" "$app/Contents/Info.plist" 2>/dev/null
}

quit_app() {
    pkill -f "$process" 2>/dev/null || true
}

quit() {
    quit_app
    local id
    id=$(bundle_id) || return 0
    # The instance's development host, if it was turned on (Window › Durable Sessions).
    for label in $(launchctl list | awk '{print $3}' | grep -F "$id.host." || true); do
        launchctl bootout "gui/$(id -u)/$label" 2>/dev/null || true
    done
}

case "$action" in
quit)
    quit
    echo "quit $name"
    exit 0
    ;;
reset)
    quit
    if id=$(bundle_id); then
        defaults delete "$id" 2>/dev/null || true
        rm -rf "$support/$id"
        channel=$(/usr/libexec/PlistBuddy -c "Print :EnvironmentVariables:NATIVE_HOST_CHANNEL" \
            "$app/Contents/Library/LaunchAgents/NativeHost.plist" 2>/dev/null || true)
        [ -n "$channel" ] && rm -rf "$support/Native/Channels/$channel"
        echo "reset $name ($id)"
    else
        echo "nothing to reset: $name was never built" >&2
    fi
    exit 0
    ;;
esac

if [ "$build" = 1 ]; then
    # Incremental, so an unchanged tree reuses the last build.
    log="$derived/build.log"
    mkdir -p "$derived"
    if ! xcodebuild -project "$root/native.xcodeproj" -scheme native -configuration Debug \
        -derivedDataPath "$derived" NATIVE_BUNDLE_IDENTIFIER_SUFFIX=".dev.$name" build >"$log" 2>&1; then
        grep -E "^/.*error:" "$log" | sort -u | head -20 >&2
        echo "build failed; full log: $log" >&2
        exit 1
    fi
fi
[ -d "$app" ] || { echo "no build at $app; run without --no-build" >&2; exit 1; }

# Relaunching replaces the app but leaves its host running, so durability and host handoffs can be
# tested by relaunching; --quit and --reset stop the host too.
quit_app
defaults_args=()
[[ " ${app_args[*]-} " == *" -agentDefaults.codex.model "* ]] || defaults_args=(-agentDefaults.codex.model gpt-6.1-sol)
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
