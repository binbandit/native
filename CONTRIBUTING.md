# Contributing

Thanks for helping. People and coding agents both contribute here, often in parallel, so the rules
are written down. [AGENTS.md](AGENTS.md) is the source of truth (where code goes, boundaries, design,
platforms, Swift style). This page is the short path to a good pull request.

## Setup

- macOS 27 with Xcode 27.1. Optional: Rust (`cargo`) for the script runtime. The terminal's Zig
  toolchain is fetched for you. Missing tools disable that feature with a build warning.
- Build: `just build` (or `xcodebuild -project native.xcodeproj -scheme native -derivedDataPath
  /tmp/native-dd/<you>-build build`). A fresh clone signs to run locally. To sign with your own team,
  put `DEVELOPMENT_TEAM = <your team id>` in `Config/Local.xcconfig`, which is never committed.
- Hooks: run `scripts/dev/install-hooks.sh` once. Commits then format and lint staged Swift files and
  check that the title is a conventional commit.
- Run: `scripts/dev/run-isolated.sh <name>`. It builds an isolated instance (own bundle id, defaults
  and host) and prints its pid and window id. `--quit` stops it, `--reset` also forgets its data.

Verify UI changes in the running app, in light and dark, not just the build.

## Previews

Every view file has a `#Preview` showing its states, so anyone can open it in Xcode's canvas and see
what they're changing: empty, loading, populated and error, long text and narrow widths. Name them
for the view and the state, like `#Preview("Composer - Queued follow-up")`.

- Wrap the content in `DSPreviewPair { … }` (`native/DesignSystem/Gallery/GalleryFixtures.swift`)
  to show it in light and dark side by side. Give flexible views a width with `.frame(width:)`.
- Sample data goes in fixtures: `<Feature>PreviewFixtures.swift` in the feature's folder, with type
  names unique in the app. Views that take models use `AppModel.preview()` and
  `SessionModel.preview(in:)` (`native/Models/AppModel+Preview.swift`), which hold realistic
  projects and tasks in memory; settings pages use `.settingsPreviewPage()`.
- Fixtures are inert: no agent processes, network, git, file writes or timers that keep running.
  Models that remember things take `PreviewUserDefaults` (in-memory) rather than the user's defaults.
- Previews and fixtures sit under `#if DEBUG`, so they never ship in Release.

## Before you open a PR

```sh
(cd Packages/<Package> && swift test)                 # every package you touched
swift format format -i <files you changed>            # .swift-format: 4 spaces, 120 columns
swift format lint --strict <files you changed>
scripts/check-ios.sh native/<YourFeature>             # models and shared views must compile for iPad
scripts/release/check.sh                              # Release and Nightly compile, if you touched #if DEBUG or build settings
```

Format only the files you change. A repo-wide lint becomes a required check after a one-time pass.

## Pull requests

- One concern per PR. Refactors and behavior changes go in separate PRs.
- Conventional commit titles: `feat(composer): queue follow-ups while a turn runs`.
- Say what was wrong or missing and how the change fixes it. Add screenshots for UI changes.
- Bug fixes start with a failing test or a reproduction.
- Update the docs you touch (`docs/keyboard.md` first for shortcuts, `docs/architecture.md`,
  `docs/decisions.md`) in the same PR.
- No third-party dependencies without a recorded reason, and no other products' brand assets.

CI runs package tests, lint on changed Swift files, the app build, and the Release and Nightly
compile. See [docs/releasing.md](docs/releasing.md) for the release workflows.

### Automated PR review

Pullfrog reviews PRs using the `Pullfrog` workflow. Its model and review triggers are configured in
the [Native repository console](https://pullfrog.com/console/binbandit/native). Automatic merging
is disabled; merging is managed separately through GitHub.

After a successful review run, `Tidy Pullfrog reviews` collapses superseded summaries while keeping
unresolved feedback and the latest substantive review visible. It can also be run manually with a
PR number. Verify changes to the cleanup workflow with:

```sh
node --test .github/tests/tidy-pullfrog-reviews.test.cjs
```

## Working as an agent

Follow the Kite rules in AGENTS.md: save with a bare `kt`, never stage, and leave history rewriting
to the coordinator. Outside this repo's shared working tree, normal git and PRs apply.

## How CI builds

`ci.yml` and `check.yml` run on `macos-26` with Xcode 27.1 by default (the repository sets the
`MACOS_RUNNER` and `XCODE_DEVELOPER_DIR` variables to GitHub's `xcode-27` preview image). They don't
install Rust: they use the `cargo` already on the runner. `check.yml` builds libghostty and the script
runtime for real and fails without them; the Debug build in `ci.yml` uses the copies Check cached.
How the jobs are split and what they cache is in `docs/releasing.md` ("How CI stays quick").
