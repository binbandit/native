#!/bin/bash
# Drives one isolated instance of Native (scripts/dev/run-isolated.sh <name>) for playtesting and for
# checking changes in the running app. The guide is docs/playtesting.md; `drive.sh <name> help` lists
# the commands.
#
#   scripts/dev/drive.sh <name> <command> [arguments…]     e.g. drive.sh playtest press "New Session"
#   scripts/dev/drive.sh <name> seed [<folder>…]          set up projects to play with (instance quit)
#   scripts/dev/drive.sh <name> seed --remove             delete them
#
# Commands act only on that instance's process, found by its name: through Accessibility, keys posted
# to its pid, and screenshots of its own windows. Nothing comes to the front and nothing is clicked
# at a position, so other people's apps never see a thing. The Swift tool behind it (scripts/dev/drive/)
# compiles on first use, and again whenever its source changes, into ~/Library/Caches/native-build/drive.
set -euo pipefail

[ $# -ge 1 ] || set -- "" help
name=$1
shift
[ $# -ge 1 ] || set -- help
root=$(git -C "$(dirname "$0")" rev-parse --show-toplevel)

# Projects to play with: a scratch clone of this repo (its origin a bare repo next to it, so pushes
# stay on this Mac) and a tiny Python repo with one failing test, written as the instance's project
# list along with Codex as the default agent. Extra folders are added after them. Also installs the
# host tests' scriptable agent as "Fake Agent", for failures on cue (docs/playtesting.md).
seed() {
    local folder="/private/tmp/native-playtest/$name"
    if [ "${1-}" = --remove ]; then
        rm -rf "$folder"
        echo "removed $folder"
        return
    fi
    if pgrep -f "native-dd/$name/Build/Products/Debug/Native.app/Contents/MacOS/Native" >/dev/null; then
        echo "$name is running, and would overwrite its project list; quit it first: scripts/dev/run-isolated.sh $name --quit" >&2
        exit 1
    fi
    local plist="/tmp/native-dd/$name/Build/Products/Debug/Native.app/Contents/Info.plist" id
    id=$(/usr/libexec/PlistBuddy -c "Print :CFBundleIdentifier" "$plist" 2>/dev/null) || {
        echo "no build for $name yet; build it first: scripts/dev/run-isolated.sh $name --build" >&2
        exit 1
    }
    [[ $id == *".dev.$name" ]] || { echo "$plist isn't $name's isolated build ($id)" >&2; exit 1; }

    mkdir -p "$folder"
    if [ ! -d "$folder/native/.git" ]; then
        # Design images are in LFS; skipping them keeps the clone off the network.
        GIT_LFS_SKIP_SMUDGE=1 git clone -q --local "$root" "$folder/native"
        git -C "$folder/native" remote remove origin
        git init -q --bare "$folder/origin.git"
        git -C "$folder/native" remote add origin "$folder/origin.git"
        git -C "$folder/native" push -q -u origin HEAD
    fi
    if [ ! -d "$folder/sample/.git" ]; then
        mkdir -p "$folder/sample"
        cat >"$folder/sample/README.md" <<'EOF'
# sample

A tiny Python project to play with. `python3 -m unittest` runs the tests; one fails on purpose.

Ideas for tasks: fix the failing test, add `--shout` to `greet.py`, add a `slugify` helper with tests.
EOF
        cat >"$folder/sample/greet.py" <<'EOF'
import sys


def greet(name: str) -> str:
    return f"Hello, {name.strip()}!"


def initials(name: str) -> str:
    return "".join(part[0] for part in name.split()).lower()


if __name__ == "__main__":
    print(greet(" ".join(sys.argv[1:]) or "world"))
EOF
        cat >"$folder/sample/test_greet.py" <<'EOF'
import unittest

from greet import greet, initials


class GreetTests(unittest.TestCase):
    def test_greet_trims(self):
        self.assertEqual(greet("  Ada "), "Hello, Ada!")

    def test_initials_are_upper_case(self):
        self.assertEqual(initials("Grace Brewster Hopper"), "GBH")


if __name__ == "__main__":
    unittest.main()
EOF
        printf '__pycache__/\n' >"$folder/sample/.gitignore"
        git -C "$folder/sample" init -q -b main
        git -C "$folder/sample" add -A
        git -C "$folder/sample" -c user.name=Playtest -c user.email=playtest@example.com commit -qm "First commit"
    fi

    # The fake agent, copied out of the build so a later rebuild doesn't swap it mid-session.
    local plugin="$folder/plugins/fake-agent" built="$HOME/Library/Caches/native-build/fake-agent"
    # At a low priority, like every build on this shared Mac (scripts/dev/build-slot.sh).
    if nice -n 10 taskpolicy -c utility swift build -q --package-path "$root/Packages/NativeHost" \
        --product FakeACPAgent --scratch-path "$built" >&2; then
        mkdir -p "$plugin" "$folder/fake-agent"
        cp -f "$built/debug/FakeACPAgent" "$plugin/FakeACPAgent"
        cat >"$plugin/plugin.json" <<JSON
{
  "id": "playtest-fake-agent",
  "name": "Fake Agent",
  "description": "A scripted agent for playtesting: crashes, network failures, approvals and slow turns on cue.",
  "agents": [{
    "id": "fake",
    "name": "Fake Agent",
    "symbol": "theatermasks",
    "command": "$plugin/FakeACPAgent",
    "env": { "FAKE_AGENT_STORE": "$folder/fake-agent" }
  }]
}
JSON
        defaults write "$id" pluginsDirectory "$folder/plugins"
    else
        echo "the fake agent didn't build (is the tree mid-change?); seeding without it" >&2
    fi

    local projects="" path
    for path in "$folder/native" "$folder/sample" "$@"; do
        [ -d "$path" ] || { echo "no folder at $path" >&2; exit 1; }
        path=$(cd "$path" && pwd -P)
        projects+="${projects:+,}{\"id\":\"$(uuidgen)\",\"url\":\"file://$path/\"}"
    done
    defaults write "$id" projects -data "$(printf '[%s]' "$projects" | xxd -p | tr -d '\n')"
    defaults write "$id" defaultAgent codex
    echo "seeded $name: projects $folder/native, $folder/sample${*:+, $*}; Codex is the default agent"
    if [ -f "$plugin/plugin.json" ]; then echo "Fake Agent installed from $plugin"; fi
}

case "$1" in
seed)
    shift
    seed "$@"
    exit 0
    ;;
logs)
    # The instance's own log lines, app and host, never another Native's: `logs [--last 10m]`, or
    # `logs --stream` to follow them.
    shift
    predicate="subsystem == \"Native\" AND processImagePath CONTAINS \"/native-dd/$name/\""
    if [ "${1-}" = --stream ]; then
        exec /usr/bin/log stream --style compact --level info --predicate "$predicate"
    fi
    last=10m
    [ "${1-}" = --last ] && last=${2:?--last takes a time, like 10m}
    exec /usr/bin/log show --style compact --info --last "$last" --predicate "$predicate"
    ;;
processes)
    # The instance's app and host, and every process under them (agents, their tools), as a tree:
    # what you may kill to test a crash, and nothing else.
    table=$(ps -A -o pid=,ppid=,command=)
    tree() {
        local pid=$1 indent=$2 child
        printf '%s%s\n' "$indent" "$(awk -v p="$pid" '$1 == p { $2 = ""; print; exit }' <<<"$table" | cut -c1-160)"
        local children
        children=$(awk -v p="$pid" '$2 == p { print $1 }' <<<"$table")
        while read -r child; do
            if [ -n "$child" ]; then tree "$child" "$indent  "; fi
        done <<<"$children"
    }
    found=0
    for pid in $(pgrep -f "native-dd/$name/Build/Products/Debug/Native.app/Contents/" || true); do
        # Only the tops: the app, and the host when launchd runs it rather than the app.
        parent=$(awk -v p="$pid" '$1 == p { print $2 }' <<<"$table")
        ps -o command= -p "$parent" 2>/dev/null | grep -qF "native-dd/$name/" && continue
        tree "$pid" ""
        found=1
    done
    [ "$found" = 1 ] || echo "$name isn't running" >&2
    exit 0
    ;;
crashes)
    # Crash and hang reports from this instance's app, host or helpers, newest first.
    grep -lF "/native-dd/$name/" ~/Library/Logs/DiagnosticReports/*.ips 2>/dev/null | xargs -r ls -t || true
    exit 0
    ;;
esac

# Compiled once per change to its source, to a temporary name first so agents starting at once don't
# run a half-written binary.
cache="$HOME/Library/Caches/native-build/drive"
sources=("$root"/scripts/dev/drive/*.swift)
hash=$(cat "${sources[@]}" | shasum -a 256 | cut -c1-16)
binary="$cache/drive-$hash"
if [ ! -x "$binary" ]; then
    mkdir -p "$cache"
    scratch=$(mktemp "$cache/build.XXXXXX")
    if ! swiftc -swift-version 6 -O "${sources[@]}" -o "$scratch" >&2; then
        rm -f "$scratch"
        echo "drive: the tool didn't compile" >&2
        exit 1
    fi
    mv -f "$scratch" "$binary"
    find "$cache" -name 'drive-*' ! -name "drive-$hash" -delete
fi
exec "$binary" "$name" "$@"
