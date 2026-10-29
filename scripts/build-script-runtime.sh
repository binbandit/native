#!/bin/bash
# Builds native-script-runtime (Runtime/ScriptRuntime) and signs it with its own App Sandbox
# entitlements. The Xcode build phase runs this to embed it at Contents/Helpers; run it by hand to
# get a signed helper for the Swift tests (Packages/ScriptRuntime) or to run the Rust tests.
#
#   scripts/build-script-runtime.sh                      build and sign into the shared cache
#   scripts/build-script-runtime.sh --test               run the crate's tests
#   scripts/build-script-runtime.sh --sandbox            build against V8 with its memory sandbox
#   scripts/build-script-runtime.sh --output <path> [--identity <id>] [--optional]
#
# The first build downloads V8's prebuilt static library (about 38 MiB, a minute or two), checked
# against the SHA-256 pinned below; later builds take seconds. --sandbox needs V8 built from
# source, which takes about an hour and 5 GiB once (Runtime/ScriptRuntime/scripts/build-v8-sandbox.py),
# or set NATIVE_V8_SANDBOX_DIR to the gn_out directory of an earlier sandbox build.
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
# Must match CFBundleIdentifier in Runtime/ScriptRuntime/Info.plist; the sandbox container is named after it.
identifier="dev.native.script-runtime"
sandbox=0
test=0
optional=0

while [ $# -gt 0 ]; do
    case "$1" in
        --output) output="$2"; shift 2 ;;
        --identity) identity="${2:--}"; shift 2 ;;
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

# The Rust the runtime ships from (Runtime/ScriptRuntime/rust-toolchain.toml): the cargo on the PATH
# when it's that version, as on CI's image, otherwise that version through rustup.
rust="$(sed -n 's/^channel = "\(.*\)"$/\1/p' "$crate/rust-toolchain.toml")"
cargo=(cargo)
if [ "$(rustc --version 2>/dev/null | cut -d' ' -f2)" != "$rust" ]; then
    if command -v rustup >/dev/null 2>&1; then
        # Installed once and then used offline (--no-update), one install at a time since several
        # builds can get here at once.
        lockf -k "${TMPDIR:-/tmp}/native-rustup-install.lock" \
            rustup toolchain install "$rust" --profile minimal --no-self-update --no-update \
            || give_up "couldn't install Rust $rust with rustup."
        # By path: a rustc earlier on the PATH (Homebrew's) would ignore rustup's choice.
        cargo=("$(rustup which --toolchain "$rust" cargo)")
        RUSTC="$(rustup which --toolchain "$rust" rustc)"
        export RUSTC
    else
        echo "note: building with $(rustc --version 2>/dev/null) rather than Rust $rust; releases use $rust (install rustup to match)."
    fi
fi

# A rustc wrapper from the user's cargo config (sccache, kache) may not be on this PATH, and this
# small crate doesn't need one: build without it so Xcode and a terminal behave the same.
export RUSTC_WRAPPER=""

export CARGO_TARGET_DIR="$cache/target"
mkdir -p "$cache"
cargo_args=(--release --locked --manifest-path "$crate/Cargo.toml")

# V8's prebuilt static library for the v8 crate in Cargo.lock (pointer compression, release, arm64).
# rusty_v8's build script would download it itself and check nothing but its URL, so it's fetched
# here, checked against these pins and handed over with RUSTY_V8_ARCHIVE. To bump the crate, update
# all three: the archive's SHA-256 is its release asset's digest, the library's is the archive's
# gunzipped content.
V8_VERSION="150.4.0"
V8_ARCHIVE_SHA256="90f2c957db016e0d1027dcc29aed62e993284cc9475240a08991ae43746f98d6"
V8_LIBRARY_SHA256="fee5f16403745c962e0d86446a75f35df608aadfa27b7c81c6e3f857acbaf5d6"

has_sha256() {
    [ -f "$1" ] && [ "$(shasum -a 256 "$1" | cut -d' ' -f1)" = "$2" ]
}

if [ "$sandbox" = 0 ]; then
    [ "$(uname -m)" = arm64 ] || give_up "V8's prebuilt library is pinned for arm64 only."
    locked="$(awk '$0 == "name = \"v8\"" { getline; gsub(/version = |"/, ""); print }' "$crate/Cargo.lock")"
    [ "$locked" = "$V8_VERSION" ] \
        || give_up "Cargo.lock has v8 $locked but this script pins $V8_VERSION; update the V8 pins in $0."
    archive="$cache/v8/librusty_v8_ptrcomp_release_aarch64-apple-darwin-$V8_VERSION.a.gz"
    if ! has_sha256 "$archive" "$V8_ARCHIVE_SHA256"; then
        # Each build downloads to its own file and renames it into place once checked, so builds
        # sharing the cache never see each other's half-written or vanished downloads.
        partial="$archive.$$.partial"
        mkdir -p "$(dirname "$archive")"
        curl -fsSL -o "$partial" \
            "https://github.com/denoland/rusty_v8/releases/download/v$V8_VERSION/librusty_v8_ptrcomp_release_aarch64-apple-darwin.a.gz" \
            || { rm -f "$partial"; give_up "couldn't download V8 $V8_VERSION."; }
        has_sha256 "$partial" "$V8_ARCHIVE_SHA256" \
            || { rm -f "$partial"; give_up "the V8 $V8_VERSION download doesn't match its pinned SHA-256."; }
        mv -f "$partial" "$archive"
    fi
    export RUSTY_V8_ARCHIVE="$archive"
fi

if [ "$sandbox" = 1 ]; then
    v8_dir="${NATIVE_V8_SANDBOX_DIR:-$cache/v8-sandbox/target/release/gn_out}"
    if [ ! -f "$v8_dir/obj/librusty_v8.a" ]; then
        python3 -I "$crate/scripts/build-v8-sandbox.py" || give_up "V8 with its memory sandbox didn't build."
    fi
    export RUSTY_V8_ARCHIVE="$v8_dir/obj/librusty_v8.a"
    export RUSTY_V8_SRC_BINDING_PATH="$v8_dir/src_binding.rs"
    # Its own target directory: V8's library sits at a fixed place in one, and the two builds
    # would keep replacing each other's.
    export CARGO_TARGET_DIR="$cache/target-sandbox"
    cargo_args+=(--features sandbox)
fi

# Some minimal rustup installations put libLLVM beside rustc's libraries, while rust-objcopy's
# rpath looks in rustlib/<target>/lib. Let the stripping tool find the pinned toolchain's library.
rust_sysroot=$("${RUSTC:-rustc}" --print sysroot)
export DYLD_FALLBACK_LIBRARY_PATH="$rust_sysroot/lib${DYLD_FALLBACK_LIBRARY_PATH:+:$DYLD_FALLBACK_LIBRARY_PATH}"

if [ "$test" = 1 ]; then
    exec "${cargo[@]}" test "${cargo_args[@]}"
fi

started=$SECONDS
"${cargo[@]}" build "${cargo_args[@]}" || give_up "native-script-runtime didn't build; see the cargo output above."
built="$CARGO_TARGET_DIR/release/native-script-runtime"
# The copy cargo linked, which a restored CI cache could have brought along unchecked.
if [ "$sandbox" = 0 ] && ! has_sha256 "$CARGO_TARGET_DIR/release/gn_out/obj/librusty_v8.a" "$V8_LIBRARY_SHA256"; then
    give_up "the V8 library in $CARGO_TARGET_DIR doesn't match its pinned SHA-256; delete that folder and build again."
fi

# Its own signature and entitlements are the second boundary: the App Sandbox with no network and
# no files outside its container, whatever happens inside V8. From Xcode it also takes the flags
# the app is signed with: a release passes --timestamp, which notarization requires, and its keychain.
sign_flags=()
if [ "$identity" != "-" ] && [ -n "${OTHER_CODE_SIGN_FLAGS:-}" ]; then
    read -r -a sign_flags <<<"$OTHER_CODE_SIGN_FLAGS"
fi
# Signed in the cache and then moved into place, so the output is never half-signed and a running
# copy keeps its file. Xcode's script sandbox lets a phase write only its declared outputs, so the
# staged copy can't sit beside the output.
mkdir -p "$(dirname "$output")"
staged="$cache/native-script-runtime.staged.$$"
cp "$built" "$staged"
# Cargo can succeed even when rustc's bundled rust-objcopy fails. Use Xcode's strip and require it
# to succeed before signing. Keep dynamic references and leave cargo's cached binary untouched.
xcrun strip -u -r -no_code_signature_warning "$staged" \
    || { rm -f "$staged"; give_up "native-script-runtime couldn't be stripped."; }
codesign --force --sign "$identity" --identifier "$identifier" --options runtime \
    ${sign_flags[@]+"${sign_flags[@]}"} --entitlements "$crate/ScriptRuntime.entitlements" "$staged" \
    || { rm -f "$staged"; give_up "native-script-runtime couldn't be signed."; }
mv -f "$staged" "$output" || { rm -f "$staged"; give_up "native-script-runtime couldn't be copied to $output."; }
echo "Built $output in $((SECONDS - started))s"
