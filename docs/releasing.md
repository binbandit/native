# Releasing

Native ships through GitHub Releases and updates itself with [Sparkle 2](https://sparkle-project.org).
There are no servers of our own: the update feeds are release assets. The decisions behind this are
in `docs/decisions.md` ("Releases on GitHub", "Sparkle for updates", "Nightly beside stable").

| Path | What lives there |
| --- | --- |
| `native/Updates/` | `UpdateController` (observable state over Sparkle), the update button, Settings ▸ Updates, Check for Updates…, the host version notice |
| `Config/*.xcconfig`, `Config/Native-Info.plist` | channels, bundle identifiers, feed URLs and the signing key, in one place |
| `scripts/release/` | `release.sh` (archive → notarize → package → appcast → publish), `check.sh` (compile Release and Nightly), `release-notes.sh`, `ci-signing.sh` |
| `.github/workflows/` | `check.yml` (every pull request), `nightly.yml` (every night), `release.yml` (on a `v*` tag) |

## Channels

| | Native (stable) | Native (beta) | Native Nightly |
| --- | --- | --- | --- |
| What it is | tested releases | the stable app, opted into betas in Settings ▸ Updates | a separate app built from `main` every night |
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

- **The update button** is Factory's: the accent tag in the sidebar's toolbar row, right of the
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
`native-host-<build>-linux-<arch>` once the host builds on Linux (TODO: the disabled `linux-host`
jobs in the workflows), and `host-feed.json` (`host-feed-beta.json` for betas, uploaded to the latest
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
| `NATIVE_SPARKLE_PUBLIC_KEY` | Sparkle's EdDSA public key → `SUPublicEDKey`. Until it's set, release builds say updates aren't set up and `release.sh --publish` refuses to run |
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
git tag v1.4.0 && git push origin v1.4.0                # CI publishes (release.yml)
```

A dry run is the default: archiving, signing, packaging and the appcast run for real (into
`$TMPDIR/native-release/<channel>`, outside the repo so quicksaves never pick them up), while
notarization and everything on GitHub is printed. `--notarize` also talks to Apple; `--publish`
does everything. On a Mac without a Developer ID identity a dry run signs ad hoc and says so; ad hoc
builds go without the hardened runtime, whose library validation would refuse to load the ad hoc
signed Sparkle framework. Nothing here depends on git hooks: the scripts only read history.

Each run: archives with `MARKETING_VERSION` and `CURRENT_PROJECT_VERSION` → copies the signed app
out of the archive → notarizes and staples it → zips it for Sparkle (`ditto`) and builds a signed,
notarized, stapled DMG for first installs (the app, an Applications link and `LICENSE.md`; the app
also carries `LICENSE.md` in its resources) → drafts notes → runs `generate_appcast` on the zip and
the published feed (so earlier items and the other channel's stay) → publishes.

- **Versions.** Stable is `v1.4.0`; beta is `v1.5.0-beta.1`. Nightly derives
  `<last stable>-nightly.<yyyymmdd>.<sha>`. The build number is the commit count of `HEAD`, so
  release from `main`, where it only grows.
- **Publishing stable and beta** creates a draft with every asset, then publishes it at once, so
  the feed never sees a half-made release. Beta also refreshes the appcast on the latest stable
  release (see "The feed URLs").
- **Publishing nightly** moves the `nightly` tag to the commit, uploads the archive (named with its
  build number, so a download in flight never meets a replaced file) and the DMG, then the appcast,
  and keeps the two newest archives.

### Release notes

Notes are drafted from conventional commits by `scripts/release/release-notes.sh <from> <to>`:
breaking changes, `feat` (New), `fix` (Fixes) and `perf` (Performance), each with its scope. Chores,
docs, tests, refactors and quicksaves stay out. The notes become the GitHub release body and are
embedded in the appcast as Markdown, which Settings ▸ Updates renders. They're generated, never
hand-edited, and there's no CHANGELOG: to change what users read, write a better commit title.

## CI

`check.yml` runs `scripts/release/check.sh` on every pull request and push to `main`: it compiles
the Release and Nightly configurations without signing, so a break that only shows up outside
Debug (a `#Preview` calling a DEBUG-only fixture) is caught before a release needs it. Run it
locally before landing anything that touches `#if DEBUG` code or build settings.

`nightly.yml` runs at 07:00 UTC (and on demand), builds `main`, and skips when `main` hasn't moved
since the last nightly. `release.yml` runs on `v*` tags. Both need Xcode with the macOS 27 SDK; set
the `MACOS_RUNNER` and `XCODE_DEVELOPER_DIR` repository variables to point them at another runner
or Xcode (defaults: `macos-26` and Xcode 27.1). `ci-signing.sh` puts the certificate and notary
credentials in a throwaway keychain and removes it afterwards.

### Repository secrets

| Secret | What it holds | How to make it |
| --- | --- | --- |
| `DEVELOPER_ID_CERTIFICATE_P12` | the Developer ID Application certificate and its private key, base64 | Keychain Access → export the identity as .p12 → `base64 -i cert.p12 \| pbcopy` |
| `DEVELOPER_ID_CERTIFICATE_PASSWORD` | the .p12's password | chosen at export |
| `NATIVE_TEAM_ID` | the Apple team id (10 characters) | developer.apple.com → Membership |
| `NOTARY_API_KEY_P8` | an App Store Connect API key for notarytool, base64 | App Store Connect → Users and Access → Integrations → Team Keys (Developer role) → download the .p8 → `base64 -i AuthKey_XXXX.p8` |
| `NOTARY_API_KEY_ID` | that key's id | shown beside the key |
| `NOTARY_API_ISSUER_ID` | the issuer id | shown above the keys |
| `SPARKLE_PRIVATE_KEY` | Sparkle's EdDSA private key | `generate_keys -x sparkle.key`, then the file's contents |

`GITHUB_TOKEN` publishes; the workflows ask for `contents: write`.

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
   private key in your login keychain and prints the public key: put that in
   `NATIVE_SPARKLE_PUBLIC_KEY`. Export the private key for CI with `generate_keys -x sparkle.key`,
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
