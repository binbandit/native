#!/bin/bash
# Hosted images include Git LFS. Bootstrap the existing CI prerequisite inside the job on runners
# that don't, without installing into the user's PATH or changing their Git configuration.
set -euo pipefail

if git -c help.autocorrect=0 lfs version >/dev/null 2>&1; then exit 0; fi

version=3.7.1
case $(uname -m) in
    arm64) arch=arm64; checksum=76260fb34f4ee622ff0a66b857e5954aa49c7e343a92e57a1ec4a760618c94b2 ;;
    x86_64) arch=amd64; checksum=b5b1b641c0648c83661fa9eda991cd3eff945264dabc2cdf411a80dfe7ec0970 ;;
    *) echo "error: unsupported Git LFS architecture" >&2; exit 1 ;;
esac
directory="${RUNNER_TEMP:?}/git-lfs"
mkdir -p "$directory"
archive="$directory/git-lfs.zip"
curl --fail --location --retry 3 \
    "https://github.com/git-lfs/git-lfs/releases/download/v$version/git-lfs-darwin-$arch-v$version.zip" \
    --output "$archive"
echo "$checksum  $archive" | shasum -a 256 --check
unzip -q -o "$archive" -d "$directory"
"$directory/git-lfs-$version/git-lfs" version
echo "$directory/git-lfs-$version" >> "${GITHUB_PATH:?}"
