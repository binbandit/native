#!/bin/bash
# Builds native-script-runtime (Runtime/ScriptRuntime) and signs it with its own App Sandbox
# entitlements. The Xcode build phase runs this to embed it at Contents/Helpers; run it by hand to
# get a signed helper for the Swift tests (Packages/ScriptRuntime) or to run the Rust tests.
#
#   scripts/build-script-runtime.sh                      build and sign into the shared cache
#   scripts/build-script-runtime.sh --test               run the crate's tests
#   scripts/build-script-runtime.sh --sandbox            build against V8 with its memory sandbox
#   scripts/build-script-runtime.sh --output <path> [--identity <id>] [--identifier <id>] [--optional]
#
# The first build downloads V8's prebuilt static library (about 37 MiB, a minute or two) into the
# cargo target directory; later builds take seconds. --sandbox needs V8 built from source, which
# takes about an hour and 5 GiB once (Runtime/ScriptRuntime/scripts/build-v8-sandbox.py), or set
# NATIVE_V8_SANDBOX_DIR to the gn_out directory of an earlier sandbox build.
#
# Builds share one cargo target directory outside the repo, ~/Library/Caches/Native/ScriptRuntime
# (override with NATIVE_SCRIPT_RUNTIME_CACHE): Xcode's script sandbox doesn't allow writing into
# the source tree, and every checkout and DerivedData folder can reuse the same V8 download.
set -euo pipefail

repo="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
crate="$repo/Runtime/ScriptRuntime"
cache="${NATIVE_SCRIPT_RUNTIME_CACHE:-$HOME/Library/Caches/Native/ScriptRuntime}"
output="$cache/native-script-runtime"
identity="-"
identifier="dev.native.script-runtime"
sandbox=0
test=0
optional=0

while [ $# -gt 0 ]; do
    case "$1" in
        --output) output="$2"; shift 2 ;;
        --identity) identity="${2:--}"; shift 2 ;;
        --identifier) identifier="$2"; shift 2 ;;
        --sandbox) sandbox=1; shift ;;
        --test) test=1; shift ;;
        # From Xcode: a missing toolchain or a failed build warns and leaves scripts disabled
        # instead of failing the app build.
        --optional) optional=1; shift ;;
        *) echo "error: unknown argument $1" >&2; exit 2 ;;
    esac
done

give_up() {
    if [ "$optional" = 1 ]; then
        echo "warning: Scripts are disabled in this build: $1"
        rm -f "$output"
        exit 0
    fi
    echo "error: $1" >&2
    exit 1
}

# Xcode runs build phases with a minimal PATH; find cargo where rustup and Homebrew put it, then
# in the user's login shell.
if ! command -v cargo >/dev/null 2>&1; then
    export PATH="$HOME/.cargo/bin:/opt/homebrew/bin:/usr/local/bin:$PATH"
fi
if ! command -v cargo >/dev/null 2>&1 && [ -n "${SHELL:-}" ]; then
    login_path="$("$SHELL" -l -c 'printf "%s" "$PATH"' 2>/dev/null || true)"
    [ -n "$login_path" ] && export PATH="$login_path:$PATH"
fi
command -v cargo >/dev/null 2>&1 || give_up "cargo isn't installed. Install Rust from https://rustup.rs and build again."

# A rustc wrapper from the user's cargo config (sccache, kache) may not be on this PATH, and this
# small crate doesn't need one: build without it so Xcode and a terminal behave the same.
export RUSTC_WRAPPER=""

export CARGO_TARGET_DIR="$cache/target"
mkdir -p "$cache"
cargo_args=(--release --manifest-path "$crate/Cargo.toml")

if [ "$sandbox" = 1 ]; then
    v8_dir="${NATIVE_V8_SANDBOX_DIR:-$CARGO_TARGET_DIR/v8-sandbox/release/gn_out}"
    if [ ! -f "$v8_dir/obj/librusty_v8.a" ]; then
        python3 -I "$crate/scripts/build-v8-sandbox.py" || give_up "V8 with its memory sandbox didn't build."
    fi
    export RUSTY_V8_ARCHIVE="$v8_dir/obj/librusty_v8.a"
    export RUSTY_V8_SRC_BINDING_PATH="$v8_dir/src_binding.rs"
    cargo_args+=(--features sandbox)
fi

if [ "$test" = 1 ]; then
    exec cargo test "${cargo_args[@]}"
fi

started=$SECONDS
cargo build "${cargo_args[@]}" || give_up "native-script-runtime didn't build; see the cargo output above."
built="$CARGO_TARGET_DIR/release/native-script-runtime"

# Its own signature and entitlements are the second boundary: the App Sandbox with no network and
# no files outside its container, whatever happens inside V8.
mkdir -p "$(dirname "$output")"
staged="$output.staged.$$"
cp "$built" "$staged"
codesign --force --sign "$identity" --identifier "$identifier" --options runtime \
    --entitlements "$crate/ScriptRuntime.entitlements" "$staged" \
    || { rm -f "$staged"; give_up "native-script-runtime couldn't be signed."; }
mv -f "$staged" "$output"
echo "Built $output in $((SECONDS - started))s"
