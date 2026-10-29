#!/bin/bash
# Offline adapters and pid-scoped keys exercise default agent switching and the legacy footer.
set -euo pipefail
instance=${1:?usage: agent-switch-keyboard.sh instance [evidence-directory]}
[[ "$instance" =~ ^[a-z0-9-]+$ ]] || exit 2
root=$(git -C "$(dirname "$0")" rev-parse --show-toplevel)
cd "$root"
evidence=${2:-"$HOME/Library/Caches/NativeDevShots/$instance/keyboard"}
fixture="/private/tmp/native-agent-switch-keyboard-$instance"
project="$root/.build/agent-switch-keyboard"
domain="dev.binbandit.native.dev.$instance"
drive() {
    [ "$(/tmp/native-tools/screenlocked)" = unlocked ] || { echo 'BLOCKED: screen locked'; exit 2; }
    scripts/dev/drive.sh "$instance" "$@"
}
run=(scripts/dev/run-isolated.sh "$instance")
[ "$(/tmp/native-tools/screenlocked)" = unlocked ] || { echo 'BLOCKED: screen locked'; exit 2; }
if drive pid >/dev/null 2>&1; then echo 'Quit the dedicated instance first'; exit 2; fi
"${run[@]}" --reset >/dev/null
mkdir -p "$evidence" "$project" "$fixture/plugins/switch"
[ -d "$project/.git" ] || git -C "$project" init -q -b main
git rev-parse HEAD >"$evidence/revision.txt"
git diff -- native scripts/tests/agent-model-change.swift scripts/tests/agent-switch-keyboard.sh >"$evidence/source.diff"
shasum -a 256 "/tmp/native-dd/$instance/Build/Products/Debug/Native.app/Contents/MacOS/Native.debug.dylib" >"$evidence/binary.sha256"
python3 - "$root" "$fixture" "$project" "$domain" <<'PY'
import json, pathlib, subprocess, sys
root, fixture, project, domain = sys.argv[1:]
agents = [dict(id=identifier, name=name, command='/usr/bin/python3', args=[
    root + '/scripts/tests/agent-model-agent.py', '--kind', kind, '--project', project,
    '--store', fixture + '/' + identifier, '--model-switch'])
    for identifier, name, kind in [('keyboard-source', 'Claude Code', 'source'), ('keyboard-target', 'Codex', 'target')]]
pathlib.Path(fixture + '/plugins/switch/plugin.json').write_text(json.dumps(dict(id='keyboard', name='Keyboard fixture', agents=agents)))
projects = json.dumps([dict(id='D1034236-92B0-4210-9F3C-F3A0A2AE7E42', url='file://' + project + '/')])
subprocess.run(['defaults','write',domain,'projects','-data',projects.encode().hex()],check=True)
subprocess.run(['defaults','write',domain,'pluginChoices','-dict', *[part for key in
    ['claude-code','codex','cursor','opencode','pi','copilot','on-device-titles','sounds']
    for part in [key,'-bool','NO']]],check=True)
PY
defaults write "$domain" experiment.NativeComposerNext -bool NO
trap '"${run[@]}" --quit >/dev/null' EXIT
"${run[@]}" --no-build -- -sounds.enabled NO -AppleKeyboardUIMode 3 -appearance.mode light \
    -pluginsDirectory "$fixture/plugins" -defaultAgent keyboard-source \
    -nativeOpenSession keyboard-source/model-source -gitHubAccountFixture signedOut >"$evidence/launch.txt"
for _ in $(seq 1 5); do
    [ "$(/tmp/native-tools/screenlocked)" = unlocked ] || exit 2
    if drive frame 100 100 1100 850 2>"$evidence/window.txt"; then break; fi
    if rg -q 'no Accessibility permission' "$evidence/window.txt"; then
        cat "$evidence/window.txt" >&2
        exit 2
    fi
    sleep 0.2
done
if ! drive frame 100 100 1100 850 2>"$evidence/window.txt"; then
    drive windows >"$evidence/windows.txt"
    if rg -q 'layer 0' "$evidence/windows.txt"; then
        echo 'BLOCKED: existing window is off screen and unavailable through Accessibility'
        exit 2
    fi
    # Reopen a saved closed main window through the app's own command (docs/playtesting.md).
    drive menu Native 'Settings…'
    drive wait Back --role AXButton --timeout 15 >/dev/null
    drive press Back --role AXButton >/dev/null
    drive frame 100 100 1100 850
fi
drive wait 'The queue now preserves its order.' --timeout 30 >/dev/null
drive press 'Model: Claude Code' >/dev/null
drive wait 'Search models' --timeout 10 >/dev/null
drive tree >"$evidence/picker.txt"
drive shot "$evidence/picker.png"
drive wait 'composer-agent-keyboard-target' --timeout 5 >/dev/null
: >"$evidence/focus.txt"
effort=0
fast=0
for _ in $(seq 1 20); do
    [ "$(/tmp/native-tools/screenlocked)" = unlocked ] || exit 2
    drive key tab
    focus=$(drive focused)
    printf '%s\n' "$focus" >>"$evidence/focus.txt"
    if [[ "$focus" == *'AXMenuButton "Low"'* ]]; then effort=1; fi
    if [[ "$focus" == *'AXCheckBox:Toggle "Fast mode"'* ]]; then fast=1; break; fi
done
drive tree >"$evidence/tree.txt"
[ "$effort" = 1 ] && [ "$fast" = 1 ] || { echo 'FAIL: Tab never reached both effort and Fast mode'; exit 1; }
drive key space
drive tree >"$evidence/fast-on.txt"
rg -q 'AXCheckBox(:Toggle)? "Fast mode" = "1"' "$evidence/fast-on.txt" || { echo 'FAIL: Space did not change Fast mode'; exit 1; }
drive key shift+tab
drive focused >"$evidence/backwards-focus.txt"
rg -q 'AXMenuButton "Low"' "$evidence/backwards-focus.txt" || { echo 'FAIL: Shift-Tab missed effort'; exit 1; }
echo 'PASS: Tab reaches effort and Fast mode, Space changes Fast mode, Shift-Tab returns to effort'
drive key escape
drive set Message 'Keep this unsent draft'
drive press 'Model: Claude Code' >/dev/null
drive press composer-agent-keyboard-target >/dev/null
drive wait 'Using Codex' --timeout 15 >/dev/null
drive key escape
drive tree >"$evidence/switched.txt"
rg -q 'AXTextArea.*Keep this unsent draft' "$evidence/switched.txt" || { echo 'FAIL: switching lost the draft'; exit 1; }
drive press 'Model: Codex' >/dev/null
drive press '6 Astra' --role AXButton >/dev/null
drive wait 'Model: Codex · 6 Astra' --timeout 10 >/dev/null
drive shot "$evidence/switched.png"
drive press 'Undo Change to Codex' --nth 0 >/dev/null
drive wait 'Model: Claude Code' --timeout 10 >/dev/null
drive tree >"$evidence/undone.txt"
rg -q 'AXTextArea.*Keep this unsent draft' "$evidence/undone.txt" || { echo 'FAIL: Undo lost the draft'; exit 1; }
python3 - "$fixture" <<'PY'
import json, pathlib, sys
for log in pathlib.Path(sys.argv[1]).glob('*/calls.jsonl'):
    assert all(json.loads(line)['method'] != 'session/prompt' for line in log.read_text().splitlines()), log
PY
echo 'PASS: default composer switches agent and model, preserves the draft and undoes without sending'
