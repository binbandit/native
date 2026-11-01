#!/bin/bash
# Exercises resource lookup outside SwiftPM's build tree, matching a binary-only host deployment.
set -euo pipefail
root=$(git -C "$(dirname "$0")" rev-parse --show-toplevel)
work=$(mktemp -d -t native-skill-deployment)
trap 'rm -rf "$work"' EXIT
cat > "$work/main.swift" <<'SWIFT'
import Foundation

do {
    let files = try NativeAgentSkill.files(cli: "/fixture/native-host")
    guard files.count == 5, files["SKILL.md"] != nil else { exit(1) }
    print("skill installed")
} catch NativeAgentSkill.Failure.resources {
    print("MCP fallback")
} catch {
    exit(1)
}
SWIFT
nice -n 10 swiftc "$root/Packages/Orchestration/Sources/NativeOrchestration/NativeAgentSkill.swift" \
    "$work/main.swift" -o "$work/native-skill-check"
[ "$("$work/native-skill-check")" = "MCP fallback" ]
# Test both the Xcode/macOS and SwiftPM/Linux resource layouts without a build-time fallback path.
for suffix in bundle resources; do
    bundle="$work/Orchestration_NativeOrchestration.$suffix"
    mkdir -p "$bundle"
    cp -R "$root/Packages/Orchestration/Sources/NativeOrchestration/Resources/native-app" "$bundle/"
    [ "$("$work/native-skill-check")" = "skill installed" ]
    rm -rf "$bundle"
done
echo "Binary-only fallback and both deployed resource layouts passed."
