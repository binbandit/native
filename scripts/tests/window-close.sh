#!/bin/bash
# Exercises Close and Quit through the isolated app's real menu and keyboard paths.
set -euo pipefail
instance=${1:?usage: window-close.sh instance [light|dark]}
appearance=${2:-dark}
root=$(git -C "$(dirname "$0")" rev-parse --show-toplevel)
drive=("$root/scripts/dev/drive.sh" "$instance")
run=("$root/scripts/dev/run-isolated.sh" "$instance")

screen() {
    local state
    if [ -x /tmp/native-tools/screenlocked ]; then
        state=$(/tmp/native-tools/screenlocked)
    else
        state=$("${drive[@]}" screen)
    fi
    [ "$state" = unlocked ] || { echo "BLOCKED: screen is locked" >&2; exit 1; }
}

fail() { echo "FAIL: $*" >&2; exit 1; }
alive() { [ "$("${drive[@]}" pid)" = "$pid" ] || fail "Close terminated or replaced the app"; }
tree() { screen; "${drive[@]}" tree --depth 1; }
await_tree() {
    local pattern=$1 present=$2 snapshot
    for _ in $(seq 1 30); do
        alive
        snapshot=$(tree)
        if [[ $snapshot == *"$pattern"* ]]; then
            [ "$present" = yes ] && return
        else
            [ "$present" = no ] && return
        fi
        sleep 0.1
    done
    fail "Expected $pattern present=$present"
}

screen
if "${drive[@]}" pid >/dev/null 2>&1; then fail "Quit $instance before testing"; fi
trap '"${run[@]}" --quit >/dev/null' EXIT
"${run[@]}" --no-build -- -appearance.mode "$appearance"
pid=$("${drive[@]}" pid)
# A previous check may have left the saved main window closed.
"${drive[@]}" menu Native 'Settings…'
await_tree '#main' yes

# An AppKit auxiliary window must close without touching the SwiftUI main window.
"${drive[@]}" menu Native 'About Native'
await_tree 'AXWindow:Dialog' yes
"${drive[@]}" key cmd+w
await_tree 'AXWindow:Dialog' no
await_tree '#main' yes

# Dismiss through the sheet's normal path, then reopen to check its binding was cleared.
for action in keyboard menu; do
    "${drive[@]}" menu Help 'Keyboard Shortcuts'
    await_tree AXSheet yes
    if [ "$action" = keyboard ]; then "${drive[@]}" key cmd+w; else "${drive[@]}" menu File Close; fi
    await_tree AXSheet no
    await_tree '#main' yes
done

# Settings occupies the main window. Closing it must keep the same app alive.
if [[ $(tree) != *'AXWindow:StandardWindow "Settings"'* ]]; then
    "${drive[@]}" menu Native 'Settings…'
fi
await_tree 'AXWindow:StandardWindow "Settings"' yes
"${drive[@]}" key cmd+w
await_tree '#main' no
alive
"${drive[@]}" menu Native 'Settings…'
await_tree '#main' yes
"${drive[@]}" key opt+cmd+w
await_tree '#main' no
alive
"${drive[@]}" menu Native 'Settings…'
await_tree '#main' yes
"${drive[@]}" key cmd+q
for _ in $(seq 1 30); do
    if ! "${drive[@]}" pid >/dev/null 2>&1; then
        echo "PASS: About, sheet dismissal/reopening, Settings, last window, Close All, reopening and Quit ($appearance)"
        exit 0
    fi
    sleep 0.1
done
fail "Cmd-Q did not quit"
