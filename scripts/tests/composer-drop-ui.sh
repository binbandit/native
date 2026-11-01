#!/bin/bash
# Run in a new isolated task in each composer and appearance. Never opens a file picker or Finder.
set -euo pipefail
instance=${1:?usage: composer-drop-ui.sh instance [capture-prefix]}
prefix=${2-}
root=$(git -C "$(dirname "$0")" rev-parse --show-toplevel)
drive=("$root/scripts/dev/drive.sh" "$instance")
fixtures="$root/scripts/tests/fixtures/composer-drop"
if [[ $(/tmp/native-tools/screenlocked) == locked ]]; then
    echo 'PENDING: screen locked; no UI checks or screenshots attempted'
    exit 75
fi
capture() {
    [[ -n $prefix ]] || return 0
    if [[ $(/tmp/native-tools/screenlocked) == locked ]]; then
        echo 'PENDING: screen locked during checks'
        exit 75
    fi
    "${drive[@]}" shot "$prefix-$1.png"
}
draft='Review these files. Keep this draft unchanged.'
"${drive[@]}" set Message "$draft"
"${drive[@]}" key cmd+l cmd+left opt+right
"${drive[@]}" drop composer "$fixtures/brief.txt" --phase hover
capture drag-over
"${drive[@]}" drop composer --phase exit
"${drive[@]}" drop composer "$fixtures/brief.txt" "$fixtures/pixel.png" "$fixtures/folder"
"${drive[@]}" wait 'Remove brief.txt'
"${drive[@]}" wait 'Remove pixel.png'
"${drive[@]}" wait 'Remove folder'
[[ $("${drive[@]}" text Message) == "$draft" ]] || { echo 'FAIL: drop changed the draft'; exit 1; }
capture attached
"${drive[@]}" drop composer "$fixtures/brief.txt"
[[ $("${drive[@]}" find 'Remove brief.txt' --role button | wc -l | tr -d ' ') == 1 ]] || {
    echo 'FAIL: duplicate attachment'; exit 1;
}
for file in brief.txt pixel.png folder; do "${drive[@]}" press "Remove $file"; done
"${drive[@]}" drop transcript "$fixtures/brief.txt"
"${drive[@]}" wait 'Remove brief.txt'
[[ $("${drive[@]}" text Message) == "$draft" ]] || { echo 'FAIL: transcript drop changed the draft'; exit 1; }
"${drive[@]}" press 'Remove brief.txt'
"${drive[@]}" key cmd+l
"${drive[@]}" paste-files "$fixtures/brief.txt" "$fixtures/pixel.png"
"${drive[@]}" wait 'Remove brief.txt'
"${drive[@]}" wait 'Remove pixel.png'
[[ $("${drive[@]}" text Message) == "$draft" ]] || { echo 'FAIL: file paste changed the draft'; exit 1; }
for file in brief.txt pixel.png; do "${drive[@]}" press "Remove $file"; done
for original in 'Before selected' 'Before `selected`'; do
    "${drive[@]}" set Message "$original"
    "${drive[@]}" key cmd+l cmd+right shift+cmd+left
    "${drive[@]}" drop composer --text 'Replaced selection'
    "${drive[@]}" wait 'Replaced selection' --role textarea
    "${drive[@]}" key cmd+z
    "${drive[@]}" wait "$original" --role textarea
    "${drive[@]}" key shift+cmd+z
    "${drive[@]}" wait 'Replaced selection' --role textarea
done
"${drive[@]}" set Message "$draft"
echo 'PASS: composer and transcript drops, multi-file and duplicate files, copied-file paste, ordinary text drop, unchanged draft'
