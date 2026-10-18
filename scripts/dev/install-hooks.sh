#!/usr/bin/env bash
# Points this clone at the repo's git hooks (.githooks): formatting and lint for staged Swift files,
# and commit message conventions. Kite's quick saves skip hooks; `kt land` and plain commits run them.
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"
chmod +x .githooks/*
git config core.hooksPath .githooks
echo "Git hooks installed from .githooks."
