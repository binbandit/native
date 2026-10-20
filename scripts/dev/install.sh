#!/bin/bash
# Builds Native and installs it in ~/Applications (no admin needed), replacing and reopening the copy
# that's running. Its background host keeps running and hands over to the new version.
#
#   scripts/dev/install.sh [Release | Nightly]                # this working tree (`just install`)
#   scripts/dev/install.sh --published [Release | Nightly]    # the latest published main (`just dev`)
#
# --published builds origin/main in a checkout of its own (/tmp/native-dev/<you>), so the Native you
# work in never carries the work in progress of this tree, yours or other agents'. Run it again to
# move to the newest main; the build is incremental.
set -euo pipefail

published=0
configuration=Release
for argument in "$@"; do
    case "$argument" in
        --published) published=1 ;;
        [Rr]elease) configuration=Release ;;
        [Nn]ightly) configuration=Nightly ;;
        *) echo "usage: $0 [--published] [Release | Nightly]" >&2; exit 2 ;;
    esac
done
case "$configuration" in
    Release) product="Native" ;;
    Nightly) product="Native Nightly" ;;
esac

root=$(git -C "$(dirname "$0")" rev-parse --show-toplevel)
user=${USER:-dev}
source=$root
derived="/tmp/native-dd/$user"
if [ "$published" = 1 ]; then
    source="/tmp/native-dev/$user"
    derived="/tmp/native-dd/$user-published"
    git -C "$root" fetch -q origin main || echo "Couldn't reach origin; installing the last main fetched." >&2
    commit=$(git -C "$root" rev-parse origin/main)
    # A checkout /tmp lost at a restart is still registered; forget it so it can be made again.
    git -C "$root" worktree prune
    # The design folder's images are LFS objects the build doesn't need.
    if [ -e "$source/.git" ]; then
        GIT_LFS_SKIP_SMUDGE=1 git -C "$source" checkout -q --force --detach "$commit"
    else
        mkdir -p "$(dirname "$source")"
        GIT_LFS_SKIP_SMUDGE=1 git -C "$root" worktree add -q --detach "$source" "$commit"
    fi
    # Signing settings are never committed: sign the same way this tree does.
    if [ -f "$root/Config/Local.xcconfig" ]; then
        cp "$root/Config/Local.xcconfig" "$source/Config/Local.xcconfig"
    else
        rm -f "$source/Config/Local.xcconfig"
    fi
    echo "Building $product ($configuration) from main at $(git -C "$root" log -1 --format='%h %s' "$commit")"
else
    echo "Building $product ($configuration) from $root"
fi

mkdir -p "$derived"
log="$derived/install.log"
echo "Build log: $log"
if ! xcodebuild -project "$source/native.xcodeproj" -scheme native -configuration "$configuration" \
    -derivedDataPath "$derived" -skipPackageUpdates build >"$log" 2>&1; then
    grep -E "^/.*error:" "$log" | sort -u | head -20 >&2
    echo "Build failed; full log: $log" >&2
    exit 1
fi

built="$derived/Build/Products/$configuration/$product.app"
target="$HOME/Applications/$product.app"
# Stop the installed copy only, matched by its path: test instances share its name. Ask it to quit,
# then make sure it's gone.
executable="$target/Contents/MacOS/$product"
if pgrep -f "^$executable" >/dev/null; then
    pkill -TERM -f "^$executable" || true
    for _ in 1 2 3 4 5 6 7 8 9 10; do pgrep -f "^$executable" >/dev/null || break; sleep 0.5; done
    pkill -KILL -f "^$executable" 2>/dev/null || true
fi
mkdir -p "$HOME/Applications"
rm -rf "$target"
ditto "$built" "$target"
echo "Installed $target"
open "$target"
