#!/bin/bash
# Exercises the MCP notice's restart callback and model without launching UI, a host or an agent.
set -euo pipefail
instance=${1:?usage: mcp-restart-notice.sh instance}
root=$(git -C "$(dirname "$0")" rev-parse --show-toplevel)
derived="/tmp/native-dd/$instance"
products="$derived/Build/Products/Debug"
app="$products/Native.app"
work=$(mktemp -d -t native-mcp-restart-notice)
trap 'rm -rf "$work"' EXIT
flags=(-I "$HOME/Library/Caches/native-build/libghostty/include" -parse-as-library -swift-version 6 -I "$products" -F "$products" -F "$products/PackageFrameworks")
for map in "$derived"/Build/Intermediates.noindex/GeneratedModuleMaps*/*.modulemap; do
    [ ! -e "$map" ] || flags+=(-Xcc "-fmodule-map-file=$map")
done
# Compile the real button callback with the model checks. SwiftUI does not expose a public way to
# invoke a Button action without starting a window; fail if its source shape changes.
python3 - "$root/native/Orchestration/OrchestrationServerNotice.swift" "$work/restart-action.swift" <<'PYTHON'
from pathlib import Path
import re
import sys

source = Path(sys.argv[1]).read_text()
actions = re.findall(r'Button\("Restart Host"\) \{(.*?)\n                \}', source, re.S)
if len(actions) != 1:
    raise SystemExit("Could not locate the MCP notice's Restart Host callback")
Path(sys.argv[2]).write_text(
    "@testable import Native\n@MainActor func pressRestartHost("
    "status: OrchestrationServerStatus, onRestartHost: () -> Void) {\n" + actions[0] + "\n}\n")
PYTHON
nice -n 10 xcrun swiftc "${flags[@]}" "$root/scripts/tests/mcp-restart-notice.swift" "$work/restart-action.swift" \
    "$app/Contents/MacOS/Native.debug.dylib" \
    -Xlinker -rpath -Xlinker "$app/Contents/Frameworks" \
    -Xlinker -rpath -Xlinker "$app/Contents/MacOS" -o "$work/mcp-restart-notice"
nice -n 10 "$work/mcp-restart-notice"
