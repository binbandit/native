#!/bin/bash
# Uses the isolated app's production constructors; contains no user configuration or credentials.
set -euo pipefail
root=$(git -C "$(dirname "$0")" rev-parse --show-toplevel)
instance=${1:-cx-mcp-to-skill}
output=${2:-/tmp/cx-mcp-to-skill-tools.json}
derived="/tmp/native-dd/$instance"
products="$derived/Build/Products/Debug"
app="$products/Native.app"
work=$(mktemp -d -t native-tool-context)
trap 'rm -rf "$work"' EXIT
flags=(-I "$HOME/Library/Caches/native-build/libghostty/include" -parse-as-library -swift-version 6 -I "$products" -F "$products" -F "$products/PackageFrameworks")
for map in "$derived"/Build/Intermediates.noindex/GeneratedModuleMaps*/*.modulemap; do
    [ ! -e "$map" ] || flags+=(-Xcc "-fmodule-map-file=$map")
done
nice -n 10 xcrun swiftc "${flags[@]}" "$root/scripts/tests/native-tool-context.swift" \
    "$app/Contents/MacOS/Native.debug.dylib" \
    -Xlinker -rpath -Xlinker "$app/Contents/Frameworks" \
    -Xlinker -rpath -Xlinker "$app/Contents/MacOS" -o "$work/native-tool-context"
"$work/native-tool-context" "$app" "$output"
python3 - "$output" <<'PY'
import json, math, sys
data = json.load(open(sys.argv[1]))
compact = lambda value: json.dumps(value, ensure_ascii=False, separators=(',', ':'))
for tool in data['tools_list']['result']['tools']:
    count = len(compact(tool))
    print(f"{tool['name']}: {count} characters, ~{math.ceil(count / 4)} tokens")
payload = len(compact(data['tools_list']))
print(f'tools/list envelope: {payload} characters')
for key in ['host_instructions', 'app_instructions']:
    count = len(data[key])
    print(f'{key}: {count} characters; total ~{math.ceil((payload + count) / 4)} tokens')
PY
