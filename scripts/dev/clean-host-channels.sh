#!/bin/sh
# Lists Native's development host jobs and channel folders, and with --apply removes the stale ones.
#
#   scripts/dev/clean-host-channels.sh [--apply] [--keep <channel>]...
#
# Each Debug build runs its own host on a channel derived from its build folder
# (docs/durability.md, "Development builds"). A channel is kept when a running Native app uses it or
# it's named with --keep; every other development host is stopped (launchctl bootout), disabled so
# it can't come back at the next login, and its folder under
# ~/Library/Application Support/Native/Channels is removed. Release hosts, whose label has no
# channel suffix, and their data in ~/Library/Application Support/Native are never touched.
set -eu

apply=0
keep=""
while [ $# -gt 0 ]; do
    case "$1" in
        --apply) apply=1 ;;
        --keep) keep="$keep $2"; shift ;;
        *) echo "usage: $0 [--apply] [--keep <channel>]..." >&2; exit 2 ;;
    esac
    shift
done

domain="gui/$(id -u)"
channels_dir="$HOME/Library/Application Support/Native/Channels"

# Channels in use: those of every running Native app, read from the plist its build generated.
for app in $(ps -axo command= | sed -n 's|^\(/.*/Native\.app\)/Contents/MacOS/Native$|\1|p' | tr ' ' '?'); do
    app=$(printf '%s' "$app" | tr '?' ' ')
    channel=$(/usr/libexec/PlistBuddy -c "Print :EnvironmentVariables:NATIVE_HOST_CHANNEL" \
        "$app/Contents/Library/LaunchAgents/NativeHost.plist" 2>/dev/null || true)
    [ -n "$channel" ] && keep="$keep $channel"
done

is_kept() {
    for kept in $keep; do [ "$kept" = "$1" ] && return 0; done
    return 1
}

run() {
    if [ "$apply" = 1 ]; then "$@" || true; else echo "    would run: $*"; fi
}

echo "Channels in use: ${keep:- none}"
found=0

# Development host jobs: labels ending in .host.<10 hex digits>, including isolated builds (.Native.dev.<name>).
for label in $(launchctl list | awk '{print $3}' | grep -E '\.Native(\.dev\.[A-Za-z0-9_-]+)?\.host\.[0-9a-f]{10}$' || true); do
    found=1
    channel=${label##*.}
    details=$(launchctl print "$domain/$label" 2>/dev/null || true)
    managed=$(printf '%s\n' "$details" | sed -n 's/^[[:space:]]*managed_by = //p' | head -1)
    pid=$(printf '%s\n' "$details" | sed -n 's/^[[:space:]]*pid = //p' | head -1)
    if is_kept "$channel"; then
        echo "keep   $label (pid ${pid:-none})"
        continue
    fi
    echo "remove $label (pid ${pid:-none}${managed:+, registered by $managed})"
    run launchctl bootout "$domain/$label"
    # A job registered through SMAppService would be loaded again at the next login.
    run launchctl disable "$domain/$label"
done

if [ -d "$channels_dir" ]; then
    for dir in "$channels_dir"/*/; do
        [ -d "$dir" ] || continue
        found=1
        channel=$(basename "$dir")
        if is_kept "$channel"; then
            echo "keep   folder $channel"
        else
            echo "remove folder $channel"
            run rm -rf "$dir"
        fi
    done
fi

[ "$found" = 0 ] && echo "No development hosts found."
[ "$apply" = 0 ] && echo "Dry run; pass --apply to remove."
exit 0
