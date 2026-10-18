# Native's everyday commands. `just` lists them. Each one wraps a script or tool the docs describe,
# so AGENTS.md and CONTRIBUTING.md stay the reference for what they do.

set shell := ["bash", "-euo", "pipefail", "-c"]

# Each person or agent builds into their own DerivedData folder, so parallel builds don't collide.
derived := "/tmp/native-dd/" + env_var_or_default("USER", "dev")

# List the recipes.
default:
    @just --list --unsorted

# Build the app (Debug, or `just build release` / `just build nightly`, in any case).
build configuration="Debug":
    #!/usr/bin/env bash
    set -euo pipefail
    # Xcode takes `release` too, but then mixes Products/release and Products/Release paths.
    configuration='{{capitalize(configuration)}}'
    case "$configuration" in
        Debug | Release | Nightly) ;;
        *) echo "error: unknown configuration '{{configuration}}'. Use Debug, Release or Nightly." >&2; exit 2 ;;
    esac
    xcodebuild -project native.xcodeproj -scheme native -configuration "$configuration" -derivedDataPath "{{derived}}" build

# Build Release (or `just install nightly`) into /Applications, replacing the old copy; settings and tasks carry over.
install configuration="Release":
    #!/usr/bin/env bash
    set -euo pipefail
    configuration='{{capitalize(configuration)}}'
    case "$configuration" in
        Release) product="Native"; id="dev.binbandit.native" ;;
        Nightly) product="Native Nightly"; id="dev.binbandit.native.nightly" ;;
        *) echo "error: install Release or Nightly, not '{{configuration}}'." >&2; exit 2 ;;
    esac
    just build "$configuration"
    # Quit only the installed app, by bundle id; test instances share its name.
    osascript -e "quit app id \"$id\"" 2>/dev/null || true
    rm -rf "/Applications/$product.app"
    ditto "{{derived}}/Build/Products/$configuration/$product.app" "/Applications/$product.app"
    echo "Installed /Applications/$product.app"
    open "/Applications/$product.app"

# Build and run an isolated instance with its own settings and data (`just run mine -- -nativeDate 2026-10-31`).
run name="dev" *args:
    scripts/dev/run-isolated.sh {{name}} {{args}}

# Measure launch, idle cost and child processes in the `perf` instance (docs/performance.md).
perf *args:
    scripts/perf/measure.sh {{args}}

# Quit an isolated instance and its host.
quit name="dev":
    scripts/dev/run-isolated.sh {{name}} --quit

# Quit an isolated instance and forget its settings and data.
reset name="dev":
    scripts/dev/run-isolated.sh {{name}} --reset

# Run one package's tests (`just test ACP`), or every package's when no name is given.
test package="":
    #!/usr/bin/env bash
    set -euo pipefail
    if [[ -n "{{package}}" ]]; then
        (cd "Packages/{{package}}" && swift test)
        exit
    fi
    failed=()
    for dir in Packages/*/; do
        name=$(basename "$dir")
        echo "== $name"
        (cd "$dir" && swift test) || failed+=("$name")
    done
    if (( ${#failed[@]} )); then
        echo "Failed: ${failed[*]}" >&2
        exit 1
    fi

# Format Swift files: the ones you changed, or the given paths.
format *paths:
    #!/usr/bin/env bash
    set -euo pipefail
    paths=({{paths}})
    if (( ${#paths[@]} == 0 )); then
        while IFS= read -r file; do paths+=("$file"); done < <(git diff --name-only --diff-filter=ACMR HEAD -- '*.swift'; git ls-files --others --exclude-standard -- '*.swift')
    fi
    (( ${#paths[@]} )) || { echo "No Swift changes."; exit; }
    swift format format --in-place "${paths[@]}"

# Lint Swift files strictly: the ones you changed, or the given paths.
lint *paths:
    #!/usr/bin/env bash
    set -euo pipefail
    paths=({{paths}})
    if (( ${#paths[@]} == 0 )); then
        while IFS= read -r file; do paths+=("$file"); done < <(git diff --name-only --diff-filter=ACMR HEAD -- '*.swift'; git ls-files --others --exclude-standard -- '*.swift')
    fi
    (( ${#paths[@]} )) || { echo "No Swift changes."; exit; }
    swift format lint --strict "${paths[@]}"

# Typecheck folders for iPadOS (`just ios native/Views/Home`).
ios +folders:
    scripts/check-ios.sh {{folders}}

# Compile the Release and Nightly configurations, as CI does.
release-check:
    scripts/release/check.sh

# Dry-run a release (`just release nightly`); see docs/releasing.md before adding --publish.
release channel *args:
    scripts/release/release.sh --channel {{channel}} {{args}}

# Build the V8 script runtime helper on its own.
script-runtime *args:
    scripts/build-script-runtime.sh {{args}}

# Build libghostty for the terminal on its own.
libghostty:
    scripts/build-libghostty.sh

# Install the repo's git hooks (format and lint staged Swift, conventional commit titles).
hooks:
    scripts/dev/install-hooks.sh

# List stray development hosts; `just clean-hosts --apply` removes them.
clean-hosts *args:
    scripts/dev/clean-host-channels.sh {{args}}
