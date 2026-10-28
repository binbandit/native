#!/bin/bash
# Resets a dedicated isolated test instance, opens a long ask and compares the complete window frame.
set -euo pipefail
instance=${1:?usage: ask-window.sh instance [light|dark] [evidence-directory] [question|confirmation|approval|failure] [pointer|keyboard]}
appearance=${2:-light}
evidence=${3:-"$HOME/Library/Caches/NativeDevShots/$instance/$appearance"}
kind=${4:-question}
input=${5:-pointer}
height=${ASK_WINDOW_HEIGHT:-700}
[[ "$instance" =~ ^[a-z0-9-]+$ ]] || { echo 'Invalid isolated instance name' >&2; exit 2; }
[[ "$appearance" = light || "$appearance" = dark ]] || exit 2
[[ "$kind" = question || "$kind" = confirmation || "$kind" = approval || "$kind" = failure ]] || exit 2
[[ "$input" = pointer || "$input" = keyboard ]] || exit 2
[[ "$height" =~ ^[0-9]+$ ]] || exit 2
root=$(git -C "$(dirname "$0")" rev-parse --show-toplevel)
drive=("$root/scripts/dev/drive.sh" "$instance")
run=("$root/scripts/dev/run-isolated.sh" "$instance")
fixture="/private/tmp/native-ask-window-$instance"
project="$root/.build/ask-window-fixture"
domain="dev.binbandit.native.dev.$instance"
screen() {
    local state
    if [ -x /tmp/native-tools/screenlocked ]; then state=$(/tmp/native-tools/screenlocked)
    else state=$("${drive[@]}" screen); fi
    [ "$state" = unlocked ] || { echo 'BLOCKED: screen is locked'; exit 1; }
}
shot() { screen; "${drive[@]}" shot "$1"; }
frame() { screen; "${drive[@]}" frame; }
visible_control() {
    screen
    "${drive[@]}" tree --frames >"$evidence/control-tree.txt"
    python3 - "$evidence/control-tree.txt" "$before" "$1" <<'PY'
import re, sys
window = list(map(int, sys.argv[2].split()))
areas = []
for line in open(sys.argv[1]):
    indent = len(line) - len(line.lstrip())
    while areas and areas[-1][0] >= indent:
        areas.pop()
    match = re.search(r'@(-?\d+),(-?\d+) (\d+)x(\d+)', line)
    if 'AXScrollArea' in line and match:
        areas.append((indent, list(map(int, match.groups()))))
    if 'AXButton "' + sys.argv[3] + '"' not in line:
        continue
    assert match and areas, line
    x, y, width, height = map(int, match.groups())
    for bounds in (window, areas[-1][1]):
        assert bounds[0] <= x and x + width <= bounds[0] + bounds[2], line
        assert bounds[1] <= y and y + height <= bounds[1] + bounds[3], line
    break
else:
    raise AssertionError('The control is missing: ' + sys.argv[3])
PY
}
screen
if "${drive[@]}" pid >/dev/null 2>&1; then echo "Quit $instance before testing" >&2; exit 1; fi
"${run[@]}" --reset
mkdir -p "$fixture/plugins/ask-window" "$project" "$fixture/store" "$evidence"
if [ ! -d "$project/.git" ]; then git -C "$project" init -q -b main; fi
git -C "$root" rev-parse HEAD >"$evidence/revision.txt"
git -C "$root" diff >"$evidence/source.diff"
shasum -a 256 "/tmp/native-dd/$instance/Build/Products/Debug/Native.app/Contents/MacOS/Native.debug.dylib" \
    >"$evidence/binary.sha256"
rm -f "$fixture/store/answer.json"
python3 - "$root" "$fixture" "$domain" "$project" "$evidence" <<'PY'
import json, pathlib, subprocess, sys
root, folder, domain, project, evidence = sys.argv[1:]
for name in ("idle.png", "ask.png", "last-choice.png", "actions.png", "output.png", "tree.txt",
             "control-tree.txt", "last-choice-tree.txt", "failure-tree.txt", "frame.txt", "windows.txt", "build.txt"):
    pathlib.Path(evidence, name).unlink(missing_ok=True)
plugin = dict(id="ask-window", name="Window fixture", agents=[dict(
    id="ask-window", name="Fake Agent", command="/usr/bin/python3", settingsFiles=[project + "/settings.toml"],
    args=[root + "/scripts/tests/ask-window-agent.py", "--project", project, "--store", folder + "/store"])])
pathlib.Path(folder + "/plugins/ask-window/plugin.json").write_text(json.dumps(plugin))
projects = json.dumps([dict(id="D1034236-92B0-4210-9F3C-F3A0A2AE7E42", url="file://" + project + "/")])
subprocess.run(["defaults", "write", domain, "projects", "-data", projects.encode().hex()], check=True)
pathlib.Path(project + "/settings.toml").write_text('mode = "fixture"\n')
PY
defaults write "$domain" experiment.NativeComposerNext -bool YES
trap '"${run[@]}" --quit >/dev/null' EXIT
launch_frame=()
if [ -n "${ASK_WINDOW_LAUNCH_FRAME:-}" ]; then launch_frame=(-nativeWindowFrame "$ASK_WINDOW_LAUNCH_FRAME"); fi
"${run[@]}" --no-build -- -appearance.mode "$appearance" -pluginsDirectory "$fixture/plugins" \
    -defaultAgent ask-window -nativeOpenSession ask-window/ask-window \
    -gitHubAccountFixture signedOut ${launch_frame[@]+"${launch_frame[@]}"}
screen
if ! "${drive[@]}" frame 100 100 1000 "$height"; then
    "${drive[@]}" windows >"$evidence/windows.txt"
    if rg -q 'layer 0' "$evidence/windows.txt"; then
        echo 'BLOCKED: the existing window is off-screen and cannot be moved through Accessibility'
        exit 1
    fi
    # The playtesting guide's reopen route for an instance whose saved main window is closed.
    "${drive[@]}" menu Native 'Settings…'
    "${drive[@]}" wait Back --role AXButton --timeout 15
    "${drive[@]}" press Back --role AXButton
    screen
    "${drive[@]}" frame 100 100 1000 "$height"
fi
"${drive[@]}" wait 'Ready to review the storage choices.' --timeout 40
screen
before=$(frame)
shot "$evidence/idle.png"
if [ "$kind" = failure ]; then
    touch "$fixture/store/fail-new"
    "${drive[@]}" press 'New Task in ask-window-fixture' --role AXButton
    "${drive[@]}" wait 'Start in Project Folder' --timeout 30
    "${drive[@]}" press 'Start in Project Folder' --role AXButton
    "${drive[@]}" wait "Fake Agent couldn't start" --timeout 30
    after=$(frame)
    shot "$evidence/ask.png"
    printf 'before: %s\nafter:  %s\n' "$before" "$after" | tee "$evidence/frame.txt"
    [ "$before" = "$after" ] || { echo 'FAIL: failed start changed the window frame'; exit 1; }
    "${drive[@]}" scroll Retry bottom
    visible_control Retry
    "${drive[@]}" press 'Show Output' --role AXButton
    shot "$evidence/output.png"
    [ "$(frame)" = "$before" ] || { echo 'FAIL: failure output changed the window frame'; exit 1; }
    "${drive[@]}" scroll Retry bottom
    visible_control Retry
    "${drive[@]}" press Retry --role AXButton
    "${drive[@]}" wait "Fake Agent couldn't start" --gone --timeout 30
    echo "PASS: failed start and expanded output stay bounded; Retry remains reachable ($appearance)"
    exit 0
fi
"${drive[@]}" set Message "$kind"
"${drive[@]}" press 'Send Message' --role AXButton
# The agent label proves Fine print is really on, rather than the legacy question dock.
if [ "$kind" = approval ]; then
    ask_label='Fake Agent wants to'
else
    ask_label='Fake Agent asks'
fi
if ! "${drive[@]}" wait "$ask_label" --timeout 30; then
    screen
    "${drive[@]}" tree --frames >"$evidence/failure-tree.txt"
    exit 1
fi
screen
after=$(frame)
"${drive[@]}" tree --frames >"$evidence/tree.txt"
shot "$evidence/ask.png"
printf 'before: %s\nafter:  %s\n' "$before" "$after" | tee "$evidence/frame.txt"
[ "$before" = "$after" ] || { echo 'FAIL: the ask changed the window frame'; exit 1; }
if [ "$kind" = question ]; then
    if [ "$input" = keyboard ]; then
        "${drive[@]}" key 9
        visible_control 'Storage choice 9'
        shot "$evidence/last-choice.png"
        "${drive[@]}" key return
    else
        "${drive[@]}" scroll 'Storage choice 9' bottom
        visible_control 'Storage choice 9'
        "${drive[@]}" press 'Storage choice 9' --role AXButton
        shot "$evidence/last-choice.png"
        "${drive[@]}" press 'Send, ↩' --role AXButton
    fi
elif [ "$kind" = confirmation ]; then
    "${drive[@]}" press 'Continue, ↩' --role AXButton
else
    "${drive[@]}" scroll 'Allow, ⌘Y' bottom
    visible_control 'Allow, ⌘Y'
    shot "$evidence/actions.png"
    "${drive[@]}" press 'Allow, ⌘Y' --role AXButton
fi
"${drive[@]}" wait 'Answer received:' --timeout 20
python3 - "$fixture/store/answer.json" "$kind" <<'PY'
import json, sys
answer = json.load(open(sys.argv[1]))
if sys.argv[2] == "approval":
    assert answer["outcome"]["optionId"] == "allow", answer
else:
    assert answer["action"] == "accept", answer
if sys.argv[2] == "question":
    assert answer["content"]["question_0"] == "9", answer
PY
answered=$(frame)
printf 'answered: %s\n' "$answered" | tee -a "$evidence/frame.txt"
[ "$answered" = "$before" ] || { echo 'FAIL: answering changed the window frame'; exit 1; }
echo "PASS: $kind opens, scrolls and answers without changing the window frame ($appearance)"
