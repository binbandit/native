#!/bin/bash
# Checks the live SwiftUI popovers through the instance's accessibility server.
# Start an unsent task with a project, all four modes and both Where choices available first.
set -euo pipefail
instance=${1:?usage: composer-menu-accessibility.sh instance}
root=$(git -C "$(dirname "$0")" rev-parse --show-toplevel)
drive="$root/scripts/dev/drive.sh"
[[ $("$drive" "$instance" screen) == unlocked ]] || { echo "BLOCKED: screen is locked" >&2; exit 2; }
tree=$("$drive" "$instance" tree)
if ! rg -q 'AXButton "Mode"' <<<"$tree" || ! rg -q 'AXButton "Where"' <<<"$tree"; then
    echo "BLOCKED: open an unsent task with accessible Mode and Where controls first" >&2
    exit 2
fi
open_menu=""
close_menu() {
    [[ -z "$open_menu" ]] || "$drive" "$instance" press "$open_menu" >/dev/null 2>&1 || true
}
trap close_menu EXIT
check_menu() {
    local menu=$1 selected=$2 tree choice
    shift 2
    "$drive" "$instance" press "$menu"
    open_menu=$menu
    tree=$("$drive" "$instance" tree)
    for choice in "$@"; do
        if ! rg -F "AXButton \"$choice\"" <<<"$tree"; then
            echo "FAIL: $menu choice has no accessible name: $choice" >&2
            exit 1
        fi
    done
    [[ $(rg -c "$selected" <<<"$tree") == 1 ]] || {
        echo "FAIL: $menu must expose exactly one selected choice" >&2
        exit 1
    }
    "$drive" "$instance" press "$menu"
    open_menu=""
    echo "PASS: $menu choices have their visible names and a selected value"
}
check_menu Mode 'AXButton "(Ask first|Accept edits|Auto|Full access)" = "Selected"' \
    'Ask first' 'Accept edits' Auto 'Full access'
check_menu Where 'AXButton "(In my folder|On a new branch)" = "Selected"' \
    'In my folder' 'On a new branch'
