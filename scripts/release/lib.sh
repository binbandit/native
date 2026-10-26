# shellcheck shell=bash
# Helpers for scripts/release. Sourced, not run. Works with macOS's bash 3.2.

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)

# MODE is "plan" (print everything, run nothing), "dry-run" (run local steps, print remote ones),
# "notarize" (also talk to Apple), "rehearse" (everything publishing does except publish) or
# "publish" (also talk to GitHub).
MODE=dry-run

log() { printf '\033[1m==>\033[0m %s\n' "$*" >&2; }
warn() { printf '\033[33mwarning:\033[0m %s\n' "$*" >&2; }
die() {
    printf '\033[31merror:\033[0m %s\n' "$*" >&2
    exit 1
}

# Prints a command the way a shell would read it back, with the Sentry DSN (a secret in CI, passed to
# xcodebuild as a build setting) left out of logs.
quoted() {
    local out="" arg dsn=${NATIVE_SENTRY_DSN:-}
    for arg in "$@"; do
        [ -z "$dsn" ] || arg=${arg//"$dsn"/<NATIVE_SENTRY_DSN>}
        out+=" $(printf '%q' "$arg")"
    done
    printf '%s' "${out# }"
}

# A step that stays on this Mac: runs unless planning.
run() {
    if [ "$MODE" = plan ]; then
        printf '  [plan] %s\n' "$(quoted "$@")" >&2
    else
        printf '  $ %s\n' "$(quoted "$@")" >&2
        "$@"
    fi
}

# A step that talks to Apple's notary service: runs with --notarize, --rehearse or --publish.
notary() {
    if [ "$MODE" = notarize ] || [ "$MODE" = rehearse ] || [ "$MODE" = publish ]; then
        run "$@"
    else
        printf '  [dry run] would run: %s\n' "$(quoted "$@")" >&2
    fi
}

# notarize <file> <credentials...>: notarizes a file and waits. notarytool exits 0 even when Apple
# rejects the file, so this reads the verdict, and on a rejection prints Apple's log of what was wrong
# before stopping. The credentials are notarytool's (--keychain-profile, and --keychain in CI).
notarize() {
    local file=$1 verdict status id
    shift
    if [ "$MODE" = plan ] || [ "$MODE" = dry-run ]; then
        notary xcrun notarytool submit "$file" "$@" --wait
        return
    fi
    printf '  $ %s\n' "$(quoted xcrun notarytool submit "$file" "$@" --wait)" >&2
    verdict=$(xcrun notarytool submit "$file" "$@" --wait --timeout 1h --output-format json) || true
    status=$(plutil -extract status raw -o - - <<<"$verdict" 2>/dev/null || true)
    id=$(plutil -extract id raw -o - - <<<"$verdict" 2>/dev/null || true)
    if [ "$status" != Accepted ]; then
        [ -z "$id" ] || xcrun notarytool log "$id" "$@" >&2 || true
        die "Apple didn't notarize $(basename "$file"): ${status:-no verdict} ${id:+(submission $id)}"
    fi
    log "Notarized $(basename "$file") (submission $id)"
}

# A step that changes GitHub: runs only with --publish.
remote() {
    if [ "$MODE" = publish ]; then
        run "$@"
    else
        printf '  [dry run] would run: %s\n' "$(quoted "$@")" >&2
    fi
}

# A build setting from Config/*.xcconfig, without resolving references.
xcconfig_value() {
    sed -n "s/^$1 *= *//p" "$ROOT/Config/$2" | tail -1
}

# owner/name of the GitHub repository; the environment wins over Config/Shared.xcconfig.
github_repository() {
    printf '%s' "${NATIVE_GITHUB_REPOSITORY:-$(xcconfig_value NATIVE_GITHUB_REPOSITORY Shared.xcconfig)}"
}

# Builds what the app embeds from outside Swift: the terminal (libghostty, fetching Zig and Ghostty
# the first time) and the script runtime (Rust and V8). Xcode's build phases only warn when they
# can't, so a build without this step would quietly ship without them; size-check.sh refuses that.
build_embedded() {
    run "$ROOT/scripts/build-libghostty.sh"
    run "$ROOT/scripts/build-script-runtime.sh"
}

# Stops unless <commit>'s .github/workflows match main's on GitHub. The workflow token can't create or
# move a tag onto a commit whose workflows differ from main's (GitHub answers 403 "Resource not
# accessible by integration"), which happens when main moves on with workflow changes while a
# nightly builds.
require_workflows_of_main() {
    run git fetch --quiet origin main || die "couldn't fetch main to compare its workflows with ${1:0:7}"
    git diff --quiet "$1" FETCH_HEAD -- .github/workflows ||
        die "main's workflows changed since ${1:0:7}, and GitHub doesn't let the workflow token tag a commit whose workflows differ from main's. Run the nightly again on main's head."
}

require_tool() {
    command -v "$1" >/dev/null 2>&1 || die "$1 isn't installed. $2"
}

# pack_update_archive <app> <archive>: Sparkle's update download. First installs keep a ZIP.
# xz at level 9 makes it about a third smaller than ditto's ZIP. Only contents, modes and symlinks go
# in: the signature and the stapled ticket live in files, and Sparkle unpacks with tar as the user,
# which restores no extended attributes, so local ones (com.apple.provenance) stay out.
pack_update_archive() {
    run /usr/bin/tar -c -J --options xz:compression-level=9 --no-mac-metadata --no-xattrs --no-acls --no-fflags \
        -f "$2" -C "$(dirname "$1")" "$(basename "$1")"
}

# update_archive_in <name without extension>: reads a release's asset names and prints its update
# archive, the .tar.xz, or the ZIP that releases before it shipped.
update_archive_in() {
    local names
    names=$(cat)
    grep -xF "$1.tar.xz" <<<"$names" || grep -xF "$1.zip" <<<"$names" || true
}

# One update archive per nightly build, preferring .tar.xz over its first-install ZIP.
nightly_update_archives() {
    local asset_base=$1
    { grep -E "^$asset_base-[0-9]+\\.(tar\\.xz|zip)$" || true; } |
        sort -t- -k3,3nr | awk -F '[-.]' '!seen[$3]++'
}

# Prints all but the last two lines: the old assets to prune, oldest first.
keep_all_but_two() {
    awk '{ a[NR] = $0 } END { for (i = 1; i <= NR - 2; i++) print a[i] }'
}

# Reads nightly asset names and prints only obsolete files. Keep the previous archive (a .tar.xz, or
# a ZIP from before), first-install ZIP and host for in-flight downloads. Icons come from latest
# stable. Retain two builds, rather than counting the two formats as separate builds.
obsolete_nightly_assets() {
    local asset_base=$1 current_deltas=$2 names
    names=$(cat)
    local builds old
    builds=$({ grep -E "^$asset_base-[0-9]+\\.(tar\\.xz|zip)$" <<<"$names" || true; } |
        sed -E "s/^$asset_base-([0-9]+)\\..*/\\1/" | sort -nu | keep_all_but_two)
    while read -r old; do
        [ -z "$old" ] || { grep -E "^$asset_base-$old\\.(tar\\.xz|zip)$" <<<"$names" || true; }
    done <<<"$builds"
    { grep -E '^native-host-[0-9]+-' <<<"$names" || true; } | sort -t- -k3 -n | keep_all_but_two
    grep -E '^(Native-Nightly\.dmg|celebration-.*\.json(\.sig)?)$' <<<"$names" || true
    { grep -E '\.delta$' <<<"$names" || true; } | while read -r name; do
        [[ $current_deltas == *" $name "* ]] || echo "$name"
    done
}
