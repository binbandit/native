#!/bin/bash
# Exercises Peek routing from the isolated Debug build with inert sessions, without opening windows.
set -euo pipefail
instance=${1:?usage: task-peek.sh instance}
root=$(git -C "$(dirname "$0")" rev-parse --show-toplevel)
derived="/tmp/native-dd/$instance"
products="$derived/Build/Products/Debug"
app="$products/Native.app"
work=$(mktemp -d -t native-task-peek)
trap 'rm -rf "$work"' EXIT
flags=(-I "$HOME/Library/Caches/native-build/libghostty/include" -parse-as-library -swift-version 6 -I "$products" -F "$products" -F "$products/PackageFrameworks")
for map in "$derived"/Build/Intermediates.noindex/GeneratedModuleMaps*/*.modulemap; do
    [ ! -e "$map" ] || flags+=(-Xcc "-fmodule-map-file=$map")
done
nice -n 10 xcrun swiftc "${flags[@]}" "$root/scripts/tests/task-peek.swift" \
    "$app/Contents/MacOS/Native.debug.dylib" \
    -Xlinker -rpath -Xlinker "$app/Contents/Frameworks" \
    -Xlinker -rpath -Xlinker "$app/Contents/MacOS" -o "$work/task-peek"
mkdir "$work/plugins"
cat > "$work/agent.py" <<'PY'
import json, sys
for line in sys.stdin:
    request = json.loads(line)
    if "id" not in request:
        continue
    result = {}
    if request.get("method") == "initialize":
        result = {"protocolVersion": 1, "agentCapabilities": {"loadSession": True}}
    print(json.dumps({"jsonrpc": "2.0", "id": request["id"], "result": result}), flush=True)
PY
"$work/task-peek" -pluginsDirectory "$work/plugins" -NativeRemoteHosts YES -peekRecoveryAgent "$work/agent.py"
