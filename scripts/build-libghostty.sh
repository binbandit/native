#!/bin/bash
# Builds libghostty, Ghostty's embedding library, for Native's terminal (native/Terminal,
# docs/terminal.md). Everything lives outside the repo, in ~/Library/Caches/native-build:
#
#   zig/<version>/            the Zig toolchain Ghostty pins (fetched; never the user's own zig)
#   ghostty/src               Ghostty's source at the pinned commit
#   ghostty/zig-cache         Zig's package and build cache for it
#   libghostty/               what Xcode uses: include/GhosttyKit, lib/libghostty.a, share/, VERSION
#
#   scripts/build-libghostty.sh             fetch the toolchain and source if needed, then build
#   scripts/build-libghostty.sh --clean     remove everything above and start over
#
# The Xcode build phase runs it with --xcode: it never touches the network, builds only when the
# toolchain and source are already here (so changing the pin below rebuilds on the next app
# build), and copies Ghostty's terminfo and shell integration into the app bundle. When libghostty
# can't be built it warns and exits 0; the app then compiles without GhosttyKit and the terminal
# shows "Terminal isn't available in this build". Xcode runs the phase only when this script (the
# pin) or libghostty/VERSION changed, or the bundle's copies are gone, so every new stage writes a
# fresh VERSION, and anything else --xcode comes to read must join the phase's inputs.
set -euo pipefail

# The pin. Ghostty's last release (1.3.1) pins Zig 0.15.2, which can't link on macOS 27 hosts, so
# Native pins a tip commit and the Zig it requires. Change all three together, and the
# decision record in docs/decisions.md.
GHOSTTY_COMMIT="b1d2b7ef1f1cf5cc0118298bad849870bc678298"
ZIG_VERSION="0.16.0"
ZIG_SHA256_AARCH64="b23d70deaa879b5c2d486ed3316f7eaa53e84acf6fc9cc747de152450d401489"
ZIG_SHA256_X86_64="0387557ed1877bc6a2e1802c8391953baddba76081876301c522f52977b52ba7"

cache="$HOME/Library/Caches/native-build"
zig_dir="$cache/zig/$ZIG_VERSION"
zig="$zig_dir/zig"
src="$cache/ghostty/src"
zig_cache="$cache/ghostty/zig-cache"
prefix="$cache/ghostty/out"
stage="$cache/libghostty"
# What a staged build was made from; a different stamp means rebuild.
stamp="ghostty=$GHOSTTY_COMMIT zig=$ZIG_VERSION flags=v1"

xcode=0
clean=0
for arg in "$@"; do
    case "$arg" in
        --xcode) xcode=1 ;;
        --clean) clean=1 ;;
        *) echo "error: unknown argument $arg" >&2; exit 2 ;;
    esac
done

# From Xcode, a missing piece warns and leaves the terminal unavailable instead of failing the
# app build; by hand it's an error.
give_up() {
    if [ "$xcode" = 1 ]; then
        echo "warning: Terminal isn't available in this build: $1"
        unstage_resources
        exit 0
    fi
    echo "error: $1" >&2
    exit 1
}

# The bundle's copy of Ghostty's resources; Ghostty finds them through
# Contents/Resources/terminfo/78/xterm-ghostty.
bundle_resources() {
    if [ -n "${TARGET_BUILD_DIR:-}" ] && [ -n "${UNLOCALIZED_RESOURCES_FOLDER_PATH:-}" ]; then
        echo "$TARGET_BUILD_DIR/$UNLOCALIZED_RESOURCES_FOLDER_PATH"
    fi
}

unstage_resources() {
    local resources
    resources="$(bundle_resources)"
    [ -n "$resources" ] || return 0
    rm -rf "$resources/terminfo" "$resources/ghostty"
}

stage_resources() {
    local resources
    resources="$(bundle_resources)"
    [ -n "$resources" ] || return 0
    mkdir -p "$resources/terminfo" "$resources/ghostty"
    rsync -a --delete "$stage/share/terminfo/" "$resources/terminfo/"
    rsync -a --delete "$stage/share/ghostty/" "$resources/ghostty/"
}

is_staged() {
    [ -f "$stage/VERSION" ] && [ "$(cat "$stage/VERSION")" = "$stamp" ] && [ -f "$stage/lib/libghostty.a" ]
}

if [ "$clean" = 1 ]; then
    rm -rf "$cache/zig/$ZIG_VERSION" "$cache/ghostty" "$stage"
    echo "Removed libghostty's toolchain, source and build from $cache."
    exit 0
fi

mkdir -p "$cache"
# One build at a time: parallel app builds (several checkouts, several agents) share this cache.
if [ -z "${NATIVE_LIBGHOSTTY_LOCKED:-}" ]; then
    exec env NATIVE_LIBGHOSTTY_LOCKED=1 lockf -k "$cache/.libghostty.lock" "$0" "$@"
fi

# The library search path Xcode links with; keeping it present avoids a linker warning.
mkdir -p "$stage/lib"

if is_staged; then
    stage_resources
    exit 0
fi

# A stale stage would compile against the wrong header: drop it before anything else.
rm -rf "$stage/include" "$stage/share" "$stage/VERSION" "$stage/lib/libghostty.a"

case "$(uname -m)" in
    arm64) zig_arch="aarch64"; zig_sha="$ZIG_SHA256_AARCH64" ;;
    x86_64) zig_arch="x86_64"; zig_sha="$ZIG_SHA256_X86_64" ;;
    *) give_up "no Zig build for $(uname -m)." ;;
esac

if [ ! -x "$zig" ] || [ "$("$zig" version 2>/dev/null)" != "$ZIG_VERSION" ]; then
    [ "$xcode" = 1 ] && give_up "Zig $ZIG_VERSION isn't in $cache. Run scripts/build-libghostty.sh once to fetch and build it."
    echo "Fetching Zig $ZIG_VERSION into $zig_dir"
    download="$(mktemp -d)"
    curl -fL --progress-bar "https://ziglang.org/download/$ZIG_VERSION/zig-$zig_arch-macos-$ZIG_VERSION.tar.xz" \
        -o "$download/zig.tar.xz" || give_up "couldn't download Zig $ZIG_VERSION."
    echo "$zig_sha  $download/zig.tar.xz" | shasum -a 256 -c - >/dev/null \
        || { rm -rf "$download"; give_up "the Zig download doesn't match its checksum."; }
    tar -xf "$download/zig.tar.xz" -C "$download"
    rm -rf "$zig_dir"
    mkdir -p "$(dirname "$zig_dir")"
    mv "$download/zig-$zig_arch-macos-$ZIG_VERSION" "$zig_dir"
    rm -rf "$download"
fi

if [ "$(git -C "$src" rev-parse HEAD 2>/dev/null || true)" != "$GHOSTTY_COMMIT" ]; then
    [ "$xcode" = 1 ] && give_up "Ghostty's source isn't in $cache. Run scripts/build-libghostty.sh once to fetch and build it."
    echo "Fetching Ghostty $GHOSTTY_COMMIT into $src"
    mkdir -p "$src"
    git -C "$src" init -q
    git -C "$src" fetch -q --depth 1 https://github.com/ghostty-org/ghostty "$GHOSTTY_COMMIT" \
        || give_up "couldn't fetch Ghostty's source."
    git -C "$src" -c advice.detachedHead=false checkout -q --force FETCH_HEAD
fi

# Xcode's build settings arrive as environment variables (SDKROOT, ARCHS, CC, ...); Zig and the
# clang it drives get a clean environment instead, so a terminal and Xcode build the same thing.
zig_env=(env -i HOME="$HOME" PATH="/usr/bin:/bin:/usr/sbin:/sbin" TMPDIR="${TMPDIR:-/tmp}")
[ -n "${DEVELOPER_DIR:-}" ] && zig_env+=(DEVELOPER_DIR="$DEVELOPER_DIR")

zig_args=(
    -Doptimize=ReleaseFast
    -Demit-xcframework=true
    -Dxcframework-target=native
    -Demit-macos-app=false
    -Demit-docs=false
    -Demit-themes=false
    # Native has its own crash reporting and strings; Ghostty's would install signal handlers
    # and link gettext into the app.
    -Dsentry=false
    -Di18n=false
    --global-cache-dir "$zig_cache"
    --prefix "$prefix"
)

if [ "$xcode" = 0 ]; then
    echo "Fetching Ghostty's Zig packages"
    (cd "$src" && "${zig_env[@]}" "$zig" build --fetch "${zig_args[@]}") || give_up "couldn't fetch Ghostty's Zig packages."
fi

# Ghostty compiles its Metal shaders with Xcode's Metal toolchain, a separate download since Xcode 26
# that fresh machines and CI images may not have.
if ! "${zig_env[@]}" xcrun -sdk macosx metal --version >/dev/null 2>&1; then
    [ "$xcode" = 1 ] && give_up "Xcode's Metal toolchain isn't installed. Run scripts/build-libghostty.sh once to download it."
    echo "Downloading Xcode's Metal toolchain"
    xcodebuild -downloadComponent MetalToolchain || give_up "couldn't download Xcode's Metal toolchain."
fi

echo "Building libghostty ($GHOSTTY_COMMIT) with Zig $ZIG_VERSION; the first build takes a few minutes"
started=$SECONDS
rm -rf "$prefix"
(cd "$src" && "${zig_env[@]}" "$zig" build "${zig_args[@]}") \
    || give_up "libghostty didn't build; see the Zig output above."

framework="$src/macos/GhosttyKit.xcframework"
library="$(find "$framework" -maxdepth 2 -name '*.a' | head -n 1)"
[ -n "$library" ] || give_up "the build didn't produce GhosttyKit.xcframework."
[ -f "$prefix/share/terminfo/78/xterm-ghostty" ] || give_up "the build didn't produce Ghostty's terminfo."

# Assemble the new stage next to the old one, then swap.
next="$stage.next"
rm -rf "$next"
mkdir -p "$next/include/GhosttyKit" "$next/lib" "$next/share/ghostty"
cp "$src/include/ghostty.h" "$next/include/GhosttyKit/ghostty.h"
cp "$library" "$next/lib/libghostty.a"
cp -R "$prefix/share/terminfo" "$next/share/terminfo"
cp -R "$prefix/share/ghostty/shell-integration" "$next/share/ghostty/shell-integration"
cp "$src/LICENSE" "$next/share/ghostty/LICENSE"
# Importing GhosttyKit links everything it needs, so the app links libghostty only when the
# module is present (Swift's `canImport(GhosttyKit)`).
cat >"$next/include/GhosttyKit/module.modulemap" <<'MODULEMAP'
module GhosttyKit {
    header "ghostty.h"
    link "ghostty"
    link "c++"
    link framework "Carbon"
    link framework "CoreText"
    link framework "IOSurface"
    link framework "Metal"
    link framework "QuartzCore"
    export *
}
MODULEMAP
echo "$stamp" >"$next/VERSION"
rm -rf "$stage"
mv "$next" "$stage"

echo "Built libghostty into $stage in $((SECONDS - started))s"
stage_resources
