#!/bin/bash
# Runs `swift build` or `swift test` for one package on another Mac, so the Mac that many agents work on
# stays usable. Packages/ is synced there first (sources only), into a folder per name, so parallel runs
# never share a checkout or a build folder.
#
#   NATIVE_REMOTE_BUILD_HOST=user@machine scripts/dev/remote-swift.sh <name> <package> build|test [swift args…]
#
# The other Mac needs the same Swift toolchain (Command Line Tools are enough) and SSH that works without
# prompts. App builds still need Xcode, so they stay local (scripts/dev/build-slot.sh).
set -euo pipefail

usage() {
    echo "usage: NATIVE_REMOTE_BUILD_HOST=user@machine $0 <name> <package> build|test [swift args…]" >&2
    exit 2
}

[ $# -ge 3 ] || usage
name=$1
package=$2
shift 2
[[ "$name" =~ ^[a-z0-9-]+$ ]] || { echo "name: lowercase letters, digits and dashes only" >&2; exit 2; }
[[ "$package" =~ ^[A-Za-z0-9_-]+$ ]] || usage
host=${NATIVE_REMOTE_BUILD_HOST:?set NATIVE_REMOTE_BUILD_HOST to user@machine}
root=$(git -C "$(dirname "$0")" rev-parse --show-toplevel)
[ -f "$root/Packages/$package/Package.swift" ] || { echo "no package at Packages/$package" >&2; exit 2; }

remote="native-remote/$name"
ssh -o BatchMode=yes "$host" mkdir -p "$remote"
rsync -a --delete --exclude .build --exclude .swiftpm "$root/Packages/" "$host:$remote/Packages/"

# The script goes over stdin to bash, so the remote login shell (whatever it is) never parses the
# arguments. Each package builds in its own scratch folder, and the host's test harness runs the
# native-host built there.
arguments=$(printf '%q ' "$@")
# Expanded here on purpose: the folder and the quoted arguments; `\$` marks what the other Mac expands.
# shellcheck disable=SC2087
ssh -o BatchMode=yes "$host" bash -s <<EOF
set -euo pipefail
scratch="\$HOME/$remote/.build/$package"
cd "\$HOME/$remote/Packages/$package"
NATIVE_HOST_TEST_PRODUCTS="\$scratch/debug" exec nice -n 5 swift $arguments --scratch-path "\$scratch"
EOF
