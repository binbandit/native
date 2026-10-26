#!/bin/bash
# Run against an isolated task with docs/guide.md and My Docs/guide.md in its fixture project.
# Use both Fine print settings and both appearances. Never submits a prompt.
set -euo pipefail
instance=${1:?usage: composer-folder-continuation.sh instance [capture-prefix]}
prefix=${2-}
root=$(git -C "$(dirname "$0")" rev-parse --show-toplevel)
drive=("$root/scripts/dev/drive.sh" "$instance")
capture() {
    [[ -n $prefix ]] || return 0
    if [[ $(/tmp/native-tools/screenlocked) == locked ]]; then
        echo 'SKIP: screen locked, capture pending' >&2
        return 0
    fi
    "${drive[@]}" shot "$prefix-$name-$1.png"
}
for folder in 'docs/' 'My Docs/'; do
    name=unquoted
    [[ $folder != *' '* ]] || name=quoted
    "${drive[@]}" set Message '@./'
    "${drive[@]}" press "$folder, folder"
    capture folder
    child=''
    for character in g u i d e; do
        child+=$character
        "${drive[@]}" type "$character"
        value=$("${drive[@]}" text Message)
        expected="@$folder$child"
        if [[ $folder == *' '* ]]; then expected="@\"$folder$child\""; fi
        if [[ $value != "$expected" ]]; then
            echo "FAIL: expected [$expected], got [$value]" >&2
            exit 1
        fi
        if [[ $child == g || $child == gu ]]; then capture "$child"; fi
    done
    "${drive[@]}" press 'guide.md'
    capture completed
    "${drive[@]}" type x
    value=$("${drive[@]}" text Message)
    # Fine print displays the completed file as a token; standard keeps its canonical @path.
    if [[ $value != *'guide.md'*' x' ]]; then
        echo "FAIL: typing after completed file: [$value]" >&2
        exit 1
    fi
    echo "PASS: $folder continuation, completion and subsequent typing"
done
