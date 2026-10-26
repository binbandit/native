#!/bin/bash
# Uses the existing socket host fixture without starting agents, apps, network or file tools.
set -euo pipefail
instance=${1:?usage: agent-model-change.sh instance}
root=$(git -C "$(dirname "$0")" rev-parse --show-toplevel)
derived="/tmp/native-dd/$instance"
products="$derived/Build/Products/Debug"
app="$products/Native.app"
work=$(mktemp -d -t native-agent-model-change)
trap 'rm -rf "$work"' EXIT
python3 - "$root" "$work/combined.swift" <<'PY'
from pathlib import Path
import sys
root = Path(sys.argv[1])
source = (root / 'scripts/tests/droid-change-agent.swift').read_text().split('@main')[0]
# The fixture reports and confirms both settings, like an ACP adapter. Keep model state when the
# permission choice is applied; a permission response is a complete config snapshot.
source = source.replace('private var failsStart = false', 'private var chosenModel = "small"\n    private var chosenMode = "read-only"\n    private var failsStart = false')
source = source.replace('static func models(_ current: String)', 'static func models(_ current: String, mode: String = "read-only")')
source = source.replace('return .update(.object(["sessionUpdate": .string("config_option_update"), "configOptions": .array([model])]))', '''let permission: JSONValue = .object([
    "id": .string("mode"), "name": .string("Permissions"), "category": .string("mode"),
    "type": .string("select"), "currentValue": .string(mode),
    "options": .array([.object(["value": .string("read-only"), "name": .string("Before any change")])])
    ])
    return .update(.object(["sessionUpdate": .string("config_option_update"), "configOptions": .array([model, permission])]))''')
source = source.replace('await log(Self.models(params.value), in: params.sessionID)', '''if params.configID == "model" { chosenModel = params.value } else { chosenMode = params.value }
        await log(Self.models(chosenModel, mode: chosenMode), in: params.sessionID)''')
Path(sys.argv[2]).write_text(source + (root / 'scripts/tests/agent-model-change.swift').read_text())
PY
flags=(-I "$HOME/Library/Caches/native-build/libghostty/include" -parse-as-library -swift-version 6 -I "$products" -F "$products" -F "$products/PackageFrameworks")
for map in "$derived"/Build/Intermediates.noindex/GeneratedModuleMaps*/*.modulemap; do
    [ ! -e "$map" ] || flags+=(-Xcc "-fmodule-map-file=$map")
done
nice -n 10 xcrun swiftc "${flags[@]}" "$work/combined.swift" "$app/Contents/MacOS/Native.debug.dylib" \
    -Xlinker -rpath -Xlinker "$app/Contents/Frameworks" -Xlinker -rpath -Xlinker "$app/Contents/MacOS" \
    -o "$work/agent-model-change"
nice -n 10 "$work/agent-model-change"
