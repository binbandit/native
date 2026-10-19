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

require_tool() {
    command -v "$1" >/dev/null 2>&1 || die "$1 isn't installed. $2"
}

# Prints all but the last two lines: the old assets to prune, oldest first.
keep_all_but_two() {
    awk '{ a[NR] = $0 } END { for (i = 1; i <= NR - 2; i++) print a[i] }'
}
