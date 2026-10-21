# Releasing

Native ships through GitHub Releases and updates itself with [Sparkle 2](https://sparkle-project.org).
There are no servers of our own: the update feeds are release assets. The decisions behind this are
in `docs/decisions.md` ("Releases on GitHub", "Sparkle for updates", "Nightly beside stable").

| Path | What lives there |
| --- | --- |
| `native/Updates/` | `UpdateController` (observable state over Sparkle), the update button, Settings ▸ Updates, Check for Updates…, the host version notice |
| `Config/*.xcconfig`, `Config/Native-Info.plist` | channels, bundle identifiers, feed URLs and the signing key, in one place |
| `Packages/HostUpdater` | how a standalone host updates itself: the signed host feed, Ed25519 checks, atomic install with rollback |
| `scripts/release/` | `release.sh` (archive → notarize → package → appcast → publish), `host.sh` (standalone host and its feed), `check.sh` (compile Release and Nightly), `size-check.sh` (the size budget, `docs/app-size.md`, and that the terminal and script runtime made it in), `sentry.sh` (dSYMs to Sentry), `release-notes.sh`, `ci-signing.sh` |
| `.github/workflows/` | `check.yml` (every pull request), `nightly.yml` (every night, or a rehearsal on demand), `beta.yml` (every six hours when main changes), `release.yml` (on a `v*` tag, called by Beta, or a rehearsal on demand), `ios.yml` (iPad and iPhone builds, daily: "iOS checks") |

## Sentry crash symbols

The Sentry project is [FoxyCorps / native](https://foxycorps.sentry.io/settings/projects/native/).
The ingestion DSN is the `NATIVE_SENTRY_DSN` repository secret, which `scripts/release/release.sh`
passes to official builds only; builds from source and forks have none and cannot start the SDK. Runtime reporting is controlled by Native's telemetry consent and
organization policy, through `SentryTelemetry.start(dsn:)` and `stop()`.
Keep **Security & Privacy → Prevent Storing of IP Addresses** enabled in the Sentry project; SDK PII
settings alone do not prevent server-side IP enrichment. Keep the advanced rule **Remove Anything
from `$user.geo.**`** as well, to discard geography added by Sentry before IP scrubbing.

To rotate an exposed ingestion key, generate a replacement in the project's
[Client Keys settings](https://foxycorps.sentry.io/settings/projects/native/keys/), update the
`NATIVE_SENTRY_DSN` repository secret, and disable the exposed key. Keep the replacement out of
source and command output. Verify it with a synthetic event and confirm the old key is disabled;
Sentry's ingestion configuration can take time to propagate. New release builds pick up the
replacement; existing builds containing the disabled DSN need an app update to report again.

Both publishing workflows read the protected `SENTRY_AUTH_TOKEN` repository secret. This is Sentry's
organization CI token named **Native GitHub release symbols**. Keep it out of source and app bundles.
For a local publication, supply the same token in the environment. `scripts/release/sentry.sh` verifies
the pinned Sentry CLI download and uploads only dSYMs, waiting for processing before the release can
publish: the archive's and the standalone `native-host`'s, which `host.sh` strips after keeping its
symbols. It does not include source bundles.
A local dry run prints this step without uploading. A rehearsal (`--rehearse`) runs
`sentry.sh --no-upload`, which finds the symbols and checks the token and project without uploading
anything; Sentry still requires the token to look up the project's upload configuration.

If symbols fail to upload, publication stops; resolve the token, network or missing-dSYMs error and
rerun the release. Release and Nightly configurations already generate dSYMs.

## Channels

| | Native (stable) | Native (beta) | Native Nightly |
| --- | --- | --- | --- |
| What it is | tested releases | the stable app, opted into betas in Settings ▸ Updates | a separate app built from `main` every night |
| When it ships | a stable version tag is pushed | every six hours if `main` has commits since the last beta, or when a beta tag is pushed | daily at 07:00 UTC if `main` has changed |
| Build configuration | Release | Release, built with `NATIVE_BETA` | Nightly (`NATIVE_NIGHTLY`) |
| Bundle identifier | `$(NATIVE_BUNDLE_IDENTIFIER_BASE)` | same | `….nightly` |
| App name | Native.app | Native.app | Native Nightly.app |
| Host | standard location | standard location | its own channel (`nightly`), so the two never share a host |
| Feed | `releases/latest/download/appcast.xml` | same feed, items tagged `<sparkle:channel>beta</sparkle:channel>` | `releases/download/nightly/appcast.xml` |
| GitHub release | `v1.4.0` | `v1.5.0-beta.1`, a prerelease | the rolling `nightly` prerelease, its assets replaced each night |
| Compiled icon | `AppIcon` | `AppIconBeta` | `AppIconNightly` |
| Tells | none | "Native Beta" (`ReleaseChannel`) and the amber/ivory icon | the name, the crescent in the toolbar, stars on the home page, its icon |

Nightly installs beside stable, like VS Code Insiders or Ghostty's tip builds: its own name, bundle
id, defaults, feed and host. Beta users get stable releases too (stable items have no channel, so
every user may install them); switching back to Stable keeps the beta until a newer stable arrives.

### The feed URLs

Both patterns were checked against real releases; Sparkle follows the redirects (all HTTPS):

- `github.com/<repo>/releases/latest/download/appcast.xml` → 302 to `…/releases/download/<tag>/appcast.xml`
  → 302 to `release-assets.githubusercontent.com` → 200.
- `github.com/<repo>/releases/download/nightly/appcast.xml` → 302 to `release-assets…` → 200.

`latest` never resolves to a prerelease or draft. Betas are prereleases, so publishing a beta also
uploads its appcast (which holds the stable and beta items) to the latest stable release. Until the
first stable release exists, beta users can't receive updates; `release.sh` warns.

## In the app

`UpdateController` wraps Sparkle with a custom user driver, so Sparkle shows no windows of its own;
everything renders from `UpdateState`:

| State | What the user sees |
| --- | --- |
| `idle` | "Native checks for updates every day", when it last checked, Check Now |
| `checking` | the loader and "Checking for updates…" on the channel |
| `upToDate` | "Native is up to date", the version, when it checked |
| `available` | version, date, size, release notes; Update, Skip This Version (not for critical updates). The toolbar button appears when automatic downloads are off |
| `downloading`, `preparing` | progress and size, Cancel while downloading. The toolbar shows "Updating" in place of the button that was clicked |
| `ready` | "Native 1.4.0 is ready to install", that it installs at quit, Restart to Update. The toolbar button appears |
| `installing` | "Installing… Native reopens in a moment" |
| `failed` | `ErrorState`: what happened, that Native is still on its version, Try Again or Open GitHub Releases (security failures never offer a retry) |
| `unavailable` | why this build can't update (development build, not set up, iPad, updater failed to start) and where releases are |

- **The update button** is the accent tag in the sidebar's toolbar row, right of the
  sidebar toggle and before back and forward (`UpdateToolbarButton`, built on the design system's
  `UpdateButton`). It shows only when there's something to do. One click downloads if needed and
  restarts into the update.
- **Restarting.** With the durable host, agents keep running while the app restarts, and the button
  says so. Without it, a restart would stop working tasks, so Native asks first and offers Restart
  When Tasks Finish. The app supplies what's running through `UpdateController.restartContext`.
- **Check for Updates…** sits in the app menu under About. It brings the main window forward, opens
  Settings ▸ Updates there (Settings lives in the window) and checks.
- **Settings ▸ Updates**: the status, version and build with a link to the release notes, the
  channel (Stable or Beta; fixed in Nightly), automatic checks and automatic downloads. Automatic
  checks and downloads are on by default (`Config/Native-Info.plist`).
- **Platforms.** Sparkle is macOS-only and linked with a macOS platform filter; on iPad the
  controller reports `unavailable(.unsupportedPlatform)` and the views compile unchanged. Only
  `SparkleUpdateDriver.swift` imports Sparkle.
- **Development builds** (`ReleaseChannel.dev`, any Debug build run from source) don't update
  themselves: `NATIVE_FEED_URL` is empty in Debug, and Settings ▸ Updates says updates are off
  because a release would replace the build.

## Updating the host

An app update replaces `Native.app`, including the host helper inside it, but the running host
keeps executing its old binary, so agents never notice the app restarting. Then:

1. The new app launches and connects. The host reports its build in `HostInfo.hostInfo.build`;
   the app compares it with its own `CFBundleVersion` (`HostVersionStatus.compare`, the same build
   number for the app and its embedded host because one `CURRENT_PROJECT_VERSION` builds both).
2. **Host older:** the app sends `_native/host/shutdown {stopAgents: false}`. The host takes no new
   turns, exits with 75 once nothing is running, and launchd starts the new binary from the updated
   bundle. Meanwhile `HostVersionNotice` says "Native updated to 1.4.0. Its background host switches
   over when your tasks finish", with Restart Host Now (the interrupted turns resume, as after any
   interruption).
3. **Host newer** (an older copy of Native was opened): the notice says this copy is older than its
   host and offers Check for Updates.
4. **Protocol versions differ:** the `initialize` handshake and `_native/host/shutdown` are frozen
   across protocol versions, so a newer app can always ask an older host to restart even when it
   can't talk to it otherwise. A newer host facing an older app is `incompatible` and shows
   "Update Native".

The host side of this (the frozen handshake, `ShutdownParams.immediately` for Restart Host Now,
`DurableHost.versionStatus`, and Nightly's own host channel) lives in `Packages/NativeHost` and
`native/Host`.

## Remote updates

An iPad or iPhone, or a Mac pointed at a Mac mini, sees when a host's Native has an update, tells
the user, and can install it, including on headless hosts (a Linux run box running only
`native-host`). Update status is a property of the **host**, served over the host protocol, so every
client asks the same question the same way.

**Who updates what.** A host reports one of three providers:

| Provider | Where | What updates | How |
| --- | --- | --- | --- |
| `app` | a Mac with Native.app | the whole app, host included (the host is inside the signed bundle, so it's never replaced alone) | Sparkle in the app (`UpdateController`). When the app isn't running, the host opens it hidden with `-NativeInstallUpdateAndQuit YES`: it checks, installs without relaunching and quits |
| `standalone` | a Linux box, or a Mac with only `native-host` (`~/.native/host`) | the `native-host` binary | the host itself, with `Packages/HostUpdater` |
| `none` | development builds, iPad | nothing | status says why |

**Protocol** (`_native/host/update/*`, shapes in `docs/durability.md`, "Updating a host remotely"):

| Method | Direction | Does |
| --- | --- | --- |
| `status` | client → host | → `HostUpdateStatus` |
| `check` | client → host | starts a check now; → the status, then `changed` as it moves |
| `install {when: idle \| now}` | client → host | installs the available update; authorized clients only |
| `changed {status}` | host → clients | the status moved |
| `report {status}` | app → host (local only) | the Mac app's Sparkle status, which the host serves as its own (provider `app`); the app sends `UpdateController.snapshot` on every change |
| `_native/app/update/install {when}` | host → app | a device's install request, for the app's Sparkle (`UpdateController.installForRemote`) |

`HostUpdateStatus`: `provider`, `current {version, build, channel}`, `state` (`idle`, `checking`,
`upToDate`, `available`, `downloading`, `ready`, `installing`, `failed`, `unavailable`; unknown
values decode as `unknown`), `available {version, build, notes, releaseNotesURL, date, size,
critical}?`, `progress?`, `message?` (the failure or why updates are off, in the words the Mac
shows), `lastChecked?`, `pendingInstall` (`idle`, `now` or null), `workingSessions` (what installing
now would interrupt), `canInstall` (computed for the asking client) and `lastRollback {from, to,
at}?`.

**Never mid-turn without consent.** `when: idle` waits until no session has a turn running or
recovering, then installs (the Mac app's Sparkle path, or a standalone host's swap) and the host
restarts through the existing exit-75 path. `when: now` is only ever sent from an explicit "Install
Now, Interrupt Tasks" on the device; interrupted turns resume like after any interruption, and the
activity journal records which device asked.

**Standalone hosts update themselves** (`Packages/HostUpdater`):

1. **Check** every 24 hours and on `check`: fetch the channel's host feed and its detached signature
   (`HostUpdateSource`), verify it with the public key compiled into the host
   (`NATIVE_SPARKLE_PUBLIC_KEY`, the appcast's key), and compare build numbers.
2. **Download** this machine's binary (exact architecture, else macOS universal), check its size,
   SHA-256 and Ed25519 signature, and stage it at `~/.native/host/versions/<build>/native-host`
   (`HostBinaryInstaller.stage`). Nothing runs it yet: state `ready`.
3. **Install** when allowed (idle, or `now`): `activate` swaps the `native-host` symlink with
   `rename(2)`, so the supervisor sees the old build or the new one, never neither; the host exits 75
   and launchd or `systemd --user` (`Restart=on-failure`) starts the new build.
4. **Confirm or roll back.** At launch the host calls `startupCheck`: a new build gets two launches
   to come up, serve and pass a handshake against its own socket, then calls `confirm`, which keeps
   it and the build before it and prunes older ones. A build that crashes or hangs (the host exits
   if it isn't confirmed within 60 seconds) is rolled back: the symlink points at the last good
   build, the host exits 75, and the status and journal say "Native Host 1.4.0 didn't start, so the
   host went back to 1.3.2".

**Host feed.** Each release also publishes the standalone host and a JSON feed beside the appcast
(`scripts/release/host.sh`): `native-host-<build>-macos-universal` (Developer ID signed, hardened
runtime, notarized; a bare binary can't be stapled, so Gatekeeper finds the ticket online),
`native-host-<build>-linux-<arch>` once the host builds on Linux (TODO: `.github/workflows/linux.yml`
builds them already; release.yml's disabled `linux-host` job, and the same for Nightly, will hand
them to release.sh as `NATIVE_LINUX_HOST_DIR`), and `host-feed.json` (`host-feed-beta.json` for betas, uploaded to the latest
stable release like the appcast) with `host-feed.json.sig`, a detached Ed25519 signature made with
the appcast's key. The feed lists each binary's platform, architecture, URL, size, SHA-256 and its
own signature (schema in `HostUpdateFeed`). The macOS host carries its version, channel, feed URL
and public key in an embedded Info.plist (`-sectcreate __TEXT __info_plist`); Linux builds will
take them from a generated source file (TODO(linux)).

## Configuration

Everything a release needs is in `Config/Shared.xcconfig`; the per-configuration files only pick
values. `Config/Native-Info.plist` is merged into the app's generated Info.plist.

| Setting | Meaning |
| --- | --- |
| `NATIVE_GITHUB_REPOSITORY` | `binbandit/native`: the feeds, release links and `release.sh`'s target |
| `NATIVE_BUNDLE_IDENTIFIER_BASE` | the app's bundle id; Nightly appends `.nightly`, the host helper `.Host` |
| `NATIVE_SPARKLE_PUBLIC_KEY` | Sparkle's EdDSA public key → `SUPublicEDKey`. Empty in the repository: official builds get it from the environment (the CI variable of the same name, which `release.sh` passes to Xcode and `host.sh`), so builds from source, `just install` included, never update themselves from Native's feed and say updates aren't set up. `release.sh --publish` refuses to run without it |
| `NATIVE_FEED_URL` | `SUFeedURL`: empty in Debug, the stable feed in Release, the nightly feed in Nightly |
| `NATIVE_CHANNEL_CONDITION` | `NATIVE_BETA` or `NATIVE_NIGHTLY`, read by `ReleaseChannel` |
| `NATIVE_HOST_CHANNEL` | `nightly` in Nightly, so its host lives apart |
| `NATIVE_PRODUCT_NAME`, `NATIVE_APP_ICON_NAME` | the app's name and compiled icon |

Release and Nightly turn on the hardened runtime (`ENABLE_HARDENED_RUNTIME`), which notarization
requires of every executable.

## Cutting a release

```sh
scripts/release/release.sh --channel nightly            # dry run: builds and packages locally, prints the rest
scripts/release/release.sh --channel stable --plan      # print every command, run nothing
scripts/release/release.sh --channel beta --version 1.5.0-beta.1 --notarize   # also notarize
gh workflow run nightly.yml --ref <branch> -f dry_run=true   # rehearse a nightly on CI, publish nothing
gh workflow run release.yml --ref <branch> -f version=1.4.0  # rehearse a stable release on CI
git tag v1.4.0 && git push origin v1.4.0                # CI publishes (release.yml)
```

A dry run is the default: archiving, signing, packaging and the appcast run for real (into
`$TMPDIR/native-release/<channel>`, outside the repo so quicksaves never pick them up), while
notarization and everything on GitHub is printed. `--notarize` also talks to Apple; `--rehearse`
does everything `--publish` does except publish (below); `--publish` does everything. On a Mac
without a Developer ID identity a dry run signs ad hoc and says so; ad hoc builds go without the
hardened runtime, whose library validation would refuse to load the ad hoc signed Sparkle framework.
Nothing here depends on git hooks: the scripts only read history.

Each run: builds the terminal and the script runtime for real (`scripts/build-libghostty.sh`,
`scripts/build-script-runtime.sh`; Xcode's build phases only warn when they can't, so this is what
keeps a release from shipping without them) → archives with `MARKETING_VERSION` and
`CURRENT_PROJECT_VERSION` → copies the signed app out of the archive → signs the helpers inside
Sparkle.framework with the Developer ID (Xcode signs the framework it embeds but leaves them ad hoc,
as Sparkle ships them, and notarization refuses ad hoc code), then the framework and the app again →
notarizes and staples it (notarytool reports a rejection without failing, so `release.sh` reads the
verdict and prints Apple's log when it isn't Accepted) → zips it for Sparkle (`ditto`) and builds a
signed, notarized, stapled DMG for first installs (the app, an Applications link and `LICENSE.md`;
the app also carries `LICENSE.md` in its resources) → checks sizes, and that the terminal and script runtime are in the app (`size-check.sh`) → drafts
notes → runs `generate_appcast` on the zip, the published feed (so earlier items and the other
channel's stay) and earlier archives for deltas → builds the standalone host → uploads symbols to
Sentry → publishes.

- **Versions.** Stable is `v1.4.0`; beta is `v1.5.0-beta.1`. Nightly derives
  `<last stable>-nightly.<yyyymmdd>.<sha>`. The build number is the commit count of `HEAD`, so
  release from `main`, where it only grows.
- **Publishing stable and beta** creates a draft with every asset, then publishes it at once, so
  the feed never sees a half-made release. Beta also refreshes the appcast on the latest stable
  release (see "The feed URLs").
- **Publishing nightly** moves the `nightly` tag to the commit, uploads the archive (named with its
  build number, so a download in flight never meets a replaced file), its deltas and the DMG, then
  the appcast, and keeps the two newest archives and only the deltas the appcast lists. GitHub won't
  let the workflow token tag a commit whose `.github/workflows` differ from `main`'s (a 403, "Resource
  not accessible by integration"), which happens when `main` moves on with workflow changes while a
  nightly builds, so `release.sh` checks that before building and again before tagging, and asks for
  a run on `main`'s head instead.

### Automatic Mac betas

`beta.yml` checks `origin/main` at 00:17, 06:17, 12:17 and 18:17 UTC. It skips with a log message
when there are no commits since the latest beta tag, or a Mac release run is active (including
queued runs). Before the first beta it compares against the latest stable tag. Version tags are
ordered numerically: `v1.5.0-beta.9` becomes `v1.5.0-beta.10`; after `v1.5.0` ships the next series
is `v1.6.0-beta.1`. A stable patch below an ongoing beta series keeps that beta series. With only
`v0.1.0` released, the first automatic beta is `v0.2.0-beta.1`.

The scheduler creates an immutable tag at the selected main commit, then calls `release.yml`
with that version, tag-based checkout and the previous beta for release notes (the last stable
for the first beta). A tag created with `GITHUB_TOKEN` does not start another workflow, so the
explicit reusable call is required. It inherits the same secrets and uses `MACOS_RUNNER` and the
same release concurrency group as a manually tagged release. Nightly, tagged stable/beta releases
and Release's direct rehearsal dispatch keep their existing behavior. This scheduler is Mac-only;
it does not call the TestFlight workflow.

Preview the decision without tagging, building, signing or publishing:

```sh
git fetch origin main 'refs/tags/v*:refs/tags/v*'
python3 scripts/release/beta-schedule.py --dry-run
gh workflow run beta.yml --ref main -f dry_run=true
```

The workflow also checks active runs during its dry run. Its manual dispatch defaults to dry run;
`dry_run=false` on `main` enables publication with the same skip checks as the schedule. A dry run
on a branch uses that branch's planner but still evaluates `origin/main`. If publishing fails after
tagging, rerun the failed release job in the original Beta run; do not move or recreate the tag.
The next scheduled check still treats that tag as the baseline.

### Rehearsing a release

`--rehearse` runs everything `--publish` does short of publishing: its checks (the Sparkle keys, the
Sentry token and DSN, a clean tree), the archive, notarizing and stapling the app, the DMG and the
standalone host, the appcast with its deltas (signed, and checked to be), the host feed, the
celebration packs, and `sentry.sh --no-upload`. Everything that would change GitHub or Sentry is
printed instead. On CI:

- `gh workflow run nightly.yml --ref <branch> -f dry_run=true` rehearses a nightly from that branch
  (the real one always builds `main`).
- `gh workflow run release.yml --ref <branch> -f version=1.4.0` rehearses a stable release, or a beta
  with `-f version=1.5.0-beta.1`. This direct dispatch never publishes; automatic betas use a
  separate reusable workflow call.

Each uploads two workflow artifacts, kept for a week: what it would have published (the update
archive, deltas, notes, appcast, DMG, standalone host and its feed, celebration packs) and the
dSYMs. Check one before the first release of its kind:

```sh
gh run download <run id> --dir rehearsal && cd rehearsal/native-nightly-<run number>
ditto -x -k appcast/Native-Nightly-*.zip check
app="check/Native Nightly.app"               # Native.app for stable and beta
codesign --verify --deep --strict --verbose=2 "$app"
spctl -a -vv "$app"                          # accepted, source=Notarized Developer ID
xcrun stapler validate "$app" && xcrun stapler validate Native-Nightly.dmg
grep -aqF "ghostty version=" "$app/Contents/MacOS/Native Nightly" && echo "libghostty is linked"
codesign -dvv "$app/Contents/Helpers/native-script-runtime"   # the script runtime, Developer ID, timestamped
plutil -extract SUPublicEDKey raw "$app/Contents/Info.plist"   # matches NATIVE_SPARKLE_PUBLIC_KEY
```

### Delta updates

Sparkle can update with a delta, the difference between two builds, instead of the whole app: a
few MB where the update archive is over 40. `generate_appcast` makes a delta from every earlier
archive in its folder to the new one, so before running it `release.sh` downloads the archives
users are most likely to have, at most three (`delta_seeds`): for stable and beta the last three
`v*` releases' archives, for nightly the ones the rolling release still holds (it keeps two). The
deltas are uploaded beside the archive and listed in the new item; a user on any other version gets
the whole archive, as before. Two details:

- `generate_appcast` points every feed item whose archive is in the folder at the new release, so
  `release.sh` puts each earlier item's original URL back.
- It names deltas after the app, `Native Nightly<new>-<old>.delta`, and GitHub turns spaces in asset
  names into dots, so Nightly's deltas are renamed with a dash, like its archives.

Seeding needs `gh`; without it, or with no earlier releases, the update simply has no deltas. A delta
needs the old build's `SUPublicEDKey` to match, which every official build has.

### Release notes

Notes are drafted from conventional commits by `scripts/release/release-notes.sh <from> <to>`:
breaking changes, `feat` (New), `fix` (Fixes) and `perf` (Performance), each with its scope. Chores,
docs, tests, refactors and quicksaves stay out, as do fixes and features scoped to how Native is built and shipped (`release`, `ci`, `build`, `deps`). The first release (no earlier tag) opens with a one-line introduction. The notes become the GitHub release body and are
embedded in the appcast as Markdown, which Settings ▸ Updates renders. They're generated, never
hand-edited, and there's no CHANGELOG: to change what users read, write a better commit title.
Automatic beta notes cover the commits since the previous beta even if a stable release was
tagged in between; `NATIVE_RELEASE_NOTES_FROM` supplies that baseline to the existing generator.

### What's New

The release notes are the full changelog. On top of them, a release can showcase a few features in
the What's New sheet (`native/WhatsNew/`): curated entries in `WhatsNewCatalog`, keyed by version,
each with a title, a one-line summary, optional original art (an asset-catalog image or an SF
Symbol that animates once) and an optional Try It that deep-links to a Settings page or a URL. Three
or four highlights per release; more page.

- It appears once, on the first launch after updating to a version with entries, collecting any
  versions skipped in between (`WhatsNewSchedule.pending`), and never on a brand-new install, where
  the landing page is the welcome.
- It waits while a task or workflow needs the user (`AppModel.hasWorkNeedingUser`, the Dock badge's
  count), so it never covers an approval; it appears as soon as nothing does.
- Esc or Continue closes it and marks the version seen. Help ▸ What's New reopens the latest
  highlights any time; Settings ▸ Updates ▸ Show What's New turns the automatic sheet off. It links
  to the release notes.
- The content model is Foundation-only, so the companion can show the same entries.
- Try it: launch with `-whatsNewVersionOverride 0.2.0 -whatsNew.lastSeenVersion 0.1.0` (an update
  from 0.1.0 to 0.2.0); without `lastSeenVersion` on a fresh instance it's a new install and stays
  quiet.

## CI

`check.yml` runs `scripts/release/check.sh` on every pull request and push to `main`: it compiles
the Release and Nightly configurations without signing, as two jobs side by side, so a break that
only shows up outside Debug (a `#Preview` calling a DEBUG-only fixture) is caught before a release
needs it, then checks each app against the size budget (`docs/app-size.md`) and for warnings. Run it
locally before landing anything that touches `#if DEBUG` code or build settings.

`nightly.yml` runs at 07:00 UTC (and on demand), builds `main`, and skips when `main` hasn't moved
since the last nightly. `beta.yml` plans a beta every six hours on Linux and calls `release.yml`
only when needed. `release.yml` also runs on `v*` tags. Nightly and Release still rehearse on demand
("Rehearsing a release"). The Check, Nightly and Release jobs need Xcode with the macOS 27 SDK; set
the `MACOS_RUNNER` and `XCODE_DEVELOPER_DIR` repository variables to point them at another runner or Xcode (defaults:
`macos-26` and Xcode 27.1; the repository uses `xcode-27` and `/Applications/Xcode.app/Contents/Developer`,
GitHub's preview image with the macOS 27 SDK). `ci-signing.sh` puts the certificate and notary
credentials in a throwaway keychain and removes it afterwards.

**What CI builds.** Everything that ships, and `check.yml`, builds the terminal and the script runtime
for real: `check.sh` and `release.sh` run `scripts/build-libghostty.sh` (fetching the pinned Zig and
Ghostty, a Zig build of several minutes) and `scripts/build-script-runtime.sh` (Rust, which the runner
image has, and a 37 MB V8 download) before Xcode, and `size-check.sh` fails an app without either.
Their outputs live in the default caches outside the checkout, because Xcode's script sandbox lets a
build phase write only its declared outputs: `~/Library/Caches/native-build/libghostty` (the staged
library, about 130 MB; the toolchain and source aren't cached) and `~/Library/Caches/Native/ScriptRuntime`
(Cargo's target folder with V8). All three workflows cache both under the same keys, keyed on the
build scripts and `Cargo.lock`, so a release restores what `main`'s checks built.

**How CI stays quick.** GitHub runs at most five macOS jobs at once for this repository, so a push
runs few: `ci.yml` runs the package tests in two macOS shards and the Debug build; changed-file lint
runs on Ubuntu in `swift:6.4`, with the same `swift format lint --strict` command. A Linux path check
skips the Debug build on PRs that only change docs or development scripts. App sources, packages,
resources, configuration, project files, embedded helpers, build scripts and the warning check still
trigger it. Main and manual runs always build. `ios.yml` already filters PRs to its build inputs,
and `check.yml` filters its two release configurations to their build inputs. Every PR workflow
cancels superseded runs for the same PR. `scripts/ci/test-packages.sh` tests every
`Packages/*/` with a `Tests` folder, so a new package can't be left out, and deals them into the
shards by the time each took on CI (`scripts/ci/package-test-times.txt`; update it from a run's
"passed in" lines when the shards drift apart, and an unlisted package counts as 30 seconds). A
third shard would only wait for a free runner. The iOS builds stay off pushes for the same reason
("iOS checks"). App builds are arm64 only (the packages declare macOS 15 and would otherwise compile
an x86_64 slice nothing links). The Debug, Release and Nightly builds also cache:

- Swift package checkouts and binary artifacts (`-clonedSourcePackagesDirPath`), keyed by the
  project's `Package.resolved`: resolving them from nothing took 3.5 minutes on CI, restoring them
  about 25 seconds.
- Xcode's compilation cache (`COMPILATION_CACHE_ENABLE_CACHING`, `check.sh --compilation-cache`), one
  per configuration. It's content-addressed, a compile's inputs being its key, so each build starts
  from an empty DerivedData and still skips every compile whose inputs haven't changed, with none of
  incremental builds' stale state; cached compiles replay their warnings, so the warnings gate sees
  them. Builds on `main` save it and pull requests only read it. `COMPILATION_CACHE_LIMIT_SIZE=2G`
  keeps it bounded: past that, Xcode starts a new generation and drops what later builds don't use.

Releases cache neither: an archive that ships compiles from scratch.

`CI_MACOS_RUNNER` overrides the runner for `ci.yml`, `check.yml` and `ios.yml`, falling back to
`MACOS_RUNNER` and then `macos-26`. Publishing in Nightly and Release keeps `MACOS_RUNNER`.
Swift package and compilation caches use keys containing the runner environment and architecture.
Package resolution and compilation caches live in `RUNNER_TEMP`, so multiple runners under the
same account never mutate the same Swift package checkout. Self-hosted jobs skip build-cache
downloads and start with fresh package build state and a job-local script runtime cache; hosted
jobs still restore their caches. The shared libghostty build already takes a lock on the machine.
Self-hosted runners need the same build tools as the hosted image, including Git LFS for artwork.

Every app build in CI, `check.sh` and `release.sh` passes `-disableAutomaticPackageResolution`, so
packages come only at the versions and revisions `Package.resolved` records. When the project's
requirements and that file disagree, the build fails ("an out-of-date resolved file was detected")
instead of resolving again against whatever the remotes have now; resolve in Xcode and commit the
file with the change that needed it.

### iOS checks

The Mac's builds never compile for iOS, so `ios.yml` does, on one runner: daily at 06:00 UTC, on
demand (`gh workflow run ios.yml --ref <branch>`), and on pull requests that touch what the iPad or
iPhone compiles (the companion and its icons, `Packages/`, the design system, the platform adapters,
the shared transcript pieces, these scripts). Not on pushes, which already take most of the five runners. Each
step runs even when the one before it failed, so one run reports every break:

- **The iPhone companion** for the iOS Simulator. It compiles some of the Mac's transcript files by
  reference (`docs/companion.md`), so a file one of them comes to need breaks it until the project
  lists that file too. Its icons are rendered from the icon work's documents, whose images are in
  Git LFS: the job fetches only those (about 50 MB), cached until the artwork changes.
- **Every package that declares iOS**, for the simulator: `scripts/ci/build-packages-ios.sh`, which
  runs the same way locally. NativeHost builds only its client; its host runs agents, which iPadOS
  can't.
- **The iPad typecheck** of the design system and the platform adapters:
  `scripts/check-ios.sh native/Platform` (the design system always comes along).

Our own files build without warnings for iOS too: every log goes through `scripts/check-warnings.sh`.
It restores the Mac builds' package checkouts, which pin the same versions, and saves no caches of its
own beyond the artwork: the repository's 10 GB is full of the Mac builds' compilation caches, which a
daily one would push out. Its compilation cache lasts for the run, so dependencies the packages
share (ACP, Exec) compile once instead of once per package: about 2.5 minutes for all of them
locally, where building each from nothing took 8.

**Not yet on iPad.** The app target is one module whose folders use each other freely (models,
plugins, commands, settings, views), so the smallest set of folders that includes `native/Models`
is the whole app, and that still imports macOS-only frameworks: ServiceManagement in `native/Host`
(`HostRegistration`, the Background settings and host notices), IOKit in the KeepAwake engine, AppKit in
`native/Terminal/Settings`, and `NativeApp.swift`, the Mac's entry point. Those move behind
`native/Platform` adapters with the iPad destination (`docs/architecture.md`, "Getting there"); add
a folder to the workflow's typecheck once it compiles there.

### iPhone TestFlight

`testflight.yml` publishes the iPhone companion (`dev.binbandit.native.companion`) after a push to
`main` leaves changes to its shipped sources or resources since the last successful upload
(`testflight-latest`, a rolling tag). It does a cheap Git diff on Linux first, so
Mac-only, documentation and test-only changes do not allocate a Mac runner or upload a build.
`scripts/companion/testflight-paths.txt` lists the companion's own sources, shared transcript and
design-system files, icon artwork and local package products. Update that list when adding a
shared file or package dependency to the companion. In particular, the NativeHost server's
implementation is excluded; its client and protocol count. The full iPad app has no archiveable
target yet and is not distributed by this workflow.

The daily TestFlight run is at 07:00 UTC, alongside the Mac Nightly but independent of its success.
It compares against the last successful mobile nightly (`testflight-nightly`, a rolling tag) and
skips when those mobile sources are unchanged. It moves the checkpoint only after Apple accepts
and processes the upload and the commit notes are attached. An upload failure therefore retries
on the next nightly. A source revert counts as a change. Daily releases use calendar versions
(`2026.10.21`, then `2026.10.22`); main builds use their commit's UTC date. All runs share the same
workflow run counter for unique Apple build numbers: run 101, attempt 1 is `2.0.1`.
The upload job allocates the number and notes itself, so rerunning only failed jobs uses the
current attempt. An older run is refused once a newer main publishing run exists; dispatch a new
main run to retry it. Rehearsals and pull requests do not supersede publishing runs. The SHA and commit subject appear in TestFlight's **What to Test** notes.
Apple's version fields remain numeric. No source-version commits are generated.

Uploads run only from `main`, never pull requests, and use `MACOS_RUNNER` (GitHub hosted), never
the persistent `CI_MACOS_RUNNER` used by PR checks. A concurrency group cancels superseded runs
so a burst of merges publishes the newest revision. Comparing against the last successful upload
keeps pending mobile changes even if a Mac-only commit replaces their original run.
The job archives Release for a real iOS device, exports a signed IPA, checks warnings, and uploads
through Apple's pinned TestFlight action. Build logs and dSYMs are retained for seven days.
Signing uses a temporary keychain and removes its credentials and installed profile even after
failure. It restores any pre-existing keychain search list and provisioning profile.

Rehearse on any branch without uploading:

```sh
gh workflow run testflight.yml --ref <branch> -f dry_run=true
```

Download the signed IPA from that run's `testflight-rehearsal-*` artifact (retained for three days).
To publish immediately from `main`, dispatch with `-f dry_run=false`; add `-f nightly=true` to use
the nightly comparison and update its checkpoint. A manual main upload always builds without
`nightly=true`. Tests for change selection and versioning run on Linux on every TestFlight run,
and on pull requests changing its workflow or scripts:

```sh
python3 -m unittest discover -s scripts/companion/tests -v
shellcheck scripts/companion/testflight-signing.sh
actionlint .github/workflows/testflight.yml
```

**One-time Apple setup:**

1. Register the explicit iOS App ID `dev.binbandit.native.companion` on Native's developer team.
   Create an iOS app record for it in App Store Connect, with primary language English (U.S.).
2. Create an Apple Distribution certificate with its private key and an **App Store Connect**
   provisioning profile for that ID. Export the identity as a password-protected `.p12`. The Mac's
   Developer ID certificate cannot sign an iOS app. Renew the certificate/profile before expiry.
3. Generate a dedicated App Store Connect **team API key**, Developer role, and store its raw `.p8`
   contents in `APP_STORE_CONNECT_API_KEY`. Store the key ID and issuer separately. This key is
   independent of the existing notarization key.
4. Add the secrets below. Never commit keys, certificates or profiles. Before the first upload,
   fill in TestFlight Test Information (Beta App Description, Feedback Email, primary locale)
   so the action can attach notes. The companion declares `ITSAppUsesNonExemptEncryption = NO`:
   its Noise transport uses Apple's CryptoKit implementations of Curve25519, ChaChaPoly, SHA-256
   and HKDF, and bundles no separate encryption implementation. This follows Apple's
   [operating-system encryption exemption](https://developer.apple.com/help/app-store-connect/manage-app-information/overview-of-export-compliance/).
   Reassess that declaration if adding another cryptographic implementation or protocol.
5. Create an **internal** TestFlight group and enable **automatic distribution**, then add the
   only the owner's App Store Connect account. The configured `Native Team` group deliberately has
   one tester; adding anyone else requires an explicit request. Apple processing and compliance
   clearance must finish before testers see a build. External testers require Apple's beta review;
   they are not an immediate per-commit distribution channel.

| Additional secret | Value |
| --- | --- |
| `IOS_DISTRIBUTION_P12` | Apple Distribution identity and private key, base64 encoded |
| `IOS_DISTRIBUTION_PASSWORD` | Password protecting that `.p12` |
| `IOS_PROVISIONING_PROFILE` | App Store Connect `.mobileprovision`, base64 encoded |
| `APP_STORE_CONNECT_API_KEY` | Raw `.p8` private-key contents (not base64) |
| `APP_STORE_CONNECT_KEY_ID` | That API key's ID |
| `APP_STORE_CONNECT_ISSUER_ID` | Team API issuer ID |

`NATIVE_TEAM_ID` is shared with the Mac release workflow. The workflow fails with a named missing
credential rather than silently skipping an upload. Apple setup also requires an active Developer
Program membership and accepted agreements. See Apple's [build upload guide](https://developer.apple.com/help/app-store-connect/manage-builds/upload-builds/)
and [internal tester setup](https://developer.apple.com/help/app-store-connect/test-a-beta-version/add-internal-testers/).

### Repository secrets

| Secret | What it holds | How to make it |
| --- | --- | --- |
| `DEVELOPER_ID_CERTIFICATE_P12` | the Developer ID Application certificate and its private key, base64 | Keychain Access → export the identity as .p12 → `base64 -i cert.p12 \| pbcopy` |
| `DEVELOPER_ID_CERTIFICATE_PASSWORD` | the .p12's password | chosen at export |
| `NATIVE_TEAM_ID` | the Apple team id (10 characters) | developer.apple.com → Membership |
| `NATIVE_SENTRY_DSN` | Sentry's client key (DSN) for official builds; source and fork builds have none | Sentry → Project Settings → Client Keys (DSN) |
| `NOTARY_API_KEY_P8` | an App Store Connect API key for notarytool, base64 | App Store Connect → Users and Access → Integrations → Team Keys (Developer role) → download the .p8 → `base64 -i AuthKey_XXXX.p8` |
| `NOTARY_API_KEY_ID` | that key's id | shown beside the key |
| `NOTARY_API_ISSUER_ID` | the issuer id | shown above the keys |
| `SPARKLE_PRIVATE_KEY` | Sparkle's EdDSA private key | `generate_keys -x sparkle.key`, then the file's contents |

`GITHUB_TOKEN` publishes; the workflows ask for `contents: write`.

### Repository variables

| Variable | What it holds |
| --- | --- |
| `NATIVE_SPARKLE_PUBLIC_KEY` | Sparkle's EdDSA public key, printed by `generate_keys`. Official builds embed it; it must be the public half of `SPARKLE_PRIVATE_KEY`, which `release.sh` checks (an appcast item it can't sign stops the release) |
| `MACOS_RUNNER` | the runner label (`xcode-27`) |
| `XCODE_DEVELOPER_DIR` | that runner's Xcode (`/Applications/Xcode.app/Contents/Developer`) |

## One-time setup

1. **Bundle identifier.** The repository is `binbandit/native`. Replace
   `NATIVE_BUNDLE_IDENTIFIER_BASE` in `Config/Shared.xcconfig` with Native's real identifier (it
   can't change after the first release without breaking updates and settings).
2. **Developer ID certificate.** In Xcode ▸ Settings ▸ Accounts ▸ Manage Certificates, add a
   Developer ID Application certificate (needs the Account Holder role). Check with
   `security find-identity -v -p codesigning`.
3. **Notarization profile** for local `--notarize` runs: create the API key above, then
   `xcrun notarytool store-credentials native-notary --key AuthKey_XXXX.p8 --key-id <id> --issuer <issuer>`.
4. **Sparkle keys.** Build once so SwiftPM fetches Sparkle, then run its `generate_keys`
   (`<DerivedData>/SourcePackages/artifacts/sparkle/Sparkle/bin/generate_keys`). It stores the
   private key in your login keychain and prints the public key: put that in the
   `NATIVE_SPARKLE_PUBLIC_KEY` repository variable. Export the private key for CI with `generate_keys -x sparkle.key`,
   store it as `SPARKLE_PRIVATE_KEY`, and delete the file. Back the key up somewhere safe: losing it
   means existing installs can't verify updates.
5. **Secrets.** Add the secrets above (`gh secret set NAME < file`).
6. **First releases.** Push `v0.1.0` (stable must exist before betas can reach anyone), then run
   the Nightly workflow by hand once to create the `nightly` release.
7. **Focus Status capability**, once a development team signs the app, so sounds stay quiet
   during Do Not Disturb and other Focus modes (`native/Sounds/Focus/SystemFocusStatus.swift`).
   Enable Focus Status for the App ID, add `com.apple.developer.focus-status` = `true` to the app's
   entitlements, and set `INFOPLIST_KEY_NSFocusStatusUsageDescription` (for example "Native stays
   quiet while a Focus is on."). Don't add the entitlement before then: macOS kills an ad hoc
   signed app that claims it at launch. Without it, Native reports that it can't see Focus, and
   Settings ▸ Sounds says so.

## Testing updates locally

An update can be tested end to end without the Keychain or GitHub: a throwaway key file, two
builds and a local feed. Use a test bundle id so it never touches your own Native's settings or
host.

```sh
work=/tmp/native-update-test && mkdir -p $work/feed $work/install
openssl genpkey -algorithm ed25519 -out $work/key.pem
openssl pkey -in $work/key.pem -outform DER | tail -c 32 | base64 > $work/sparkle.key   # private seed
public=$(openssl pkey -in $work/key.pem -pubout -outform DER | tail -c 32 | base64)
common=(--channel stable --no-dmg --ed-key-file $work/sparkle.key --download-url-prefix http://127.0.0.1:8765/
  --build-setting NATIVE_FEED_URL=http://127.0.0.1:8765/appcast.xml --build-setting NATIVE_SPARKLE_PUBLIC_KEY=$public
  --build-setting NATIVE_BUNDLE_IDENTIFIER_BASE=dev.native.updatetest)
scripts/release/release.sh "${common[@]}" --version 1.0.0 --build-number 1000 --output $work/old
scripts/release/release.sh "${common[@]}" --version 1.1.0 --build-number 1001 --output $work/new
cp $work/new/appcast/appcast.xml $work/new/appcast/*.zip $work/feed/
(cd $work/feed && python3 -m http.server 8765 --bind 127.0.0.1) &
ditto $work/old/Native.app $work/install/Native.app && open -n $work/install/Native.app
```

The key is a raw Ed25519 seed in a file, so nothing touches the Keychain, and the test bundle id
keeps the test away from your own Native's settings and host. With automatic downloads on, 1.0.0
downloads 1.1.0 in the background right after launch; Native ▸ Check for Updates… opens Settings ▸
Updates showing "Native 1.1.0 is ready to install" with its notes, and Restart to Update relaunches
as 1.1.0 (verified 2026-10-18, ad hoc signed, arm64). Afterwards stop the server, delete
`$work`, `defaults delete dev.native.updatetest` and `~/Library/Caches/dev.native.updatetest`.

## Channel and seasonal icons

The release script selects the compiled icon with `NATIVE_APP_ICON_NAME`: `AppIcon` for stable,
`AppIconBeta` for beta, and `AppIconNightly` for Nightly. Beta keeps the stable app's identity and
update feed; the dedicated icon identifies the installed build. The compiled channel icons retain
macOS Default, Dark, Clear and Tinted appearances. Source projects live in `design/app-icon/`.

Debug builds launched from Xcode or `scripts/dev/run-isolated.sh` use `AppIconDev`, with a cyan
blueprint treatment and code signature. This development icon identity is independent of the
release channel, so previewing Beta or Nightly in a Debug build still uses the development icon.
Original restores the compiled development icon and its native system appearances.

Settings ▸ Appearance offers Halloween editions from October 1 through November 7, inclusive,
in the device's local time zone. Each build uses its own Halloween artwork, with the development
edition in Debug builds even while previewing another release channel. The seasonal toggle
remembers the user's opt-in, preserves their usual icon choice, and restores it on November 8.
Choosing another icon turns Halloween off immediately. The seasonal option and View ▸ Halloween
Icon disappear outside the window; a stored opt-in cannot activate an out-of-season icon.
Availability refreshes at the next boundary and on activation, wake, clock and time-zone changes.
`Packages/AppAppearance` owns and tests the date policy. Seasonal Dock overrides use light/dark
PNGs rendered by Icon Composer, with editable layered `.icon` sources retained alongside them.
