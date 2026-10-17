# Releasing

Native ships through GitHub Releases and updates itself with [Sparkle 2](https://sparkle-project.org).
There are no servers of our own: the update feeds are release assets. The decisions behind this are
in `docs/decisions.md` ("Releases on GitHub", "Sparkle for updates", "Nightly beside stable").

| Path | What lives there |
| --- | --- |
| `native/Updates/` | `UpdateController` (observable state over Sparkle), the update button, Settings ▸ Updates, the Software Update window, the host version notice |
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
| Tells | none | "Native Beta" (`ReleaseChannel`) | the name, the crescent in the toolbar, stars on the home page, its icon |

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
- **Check for Updates…** sits in the app menu under About and opens the Software Update window,
  which shows the same status view as Settings ▸ Updates.
- **Settings ▸ Updates**: the status, version and build with a link to the release notes, the
  channel (Stable or Beta; fixed in Nightly), automatic checks and automatic downloads. Automatic
  checks and downloads are on by default (`Config/Native-Info.plist`).
- **Platforms.** Sparkle is macOS-only and linked with a macOS platform filter; on iPad the
  controller reports `unavailable(.unsupportedPlatform)` and the views compile unchanged. Only
  `SparkleUpdateDriver.swift` imports Sparkle.
- **Development builds** don't update themselves (`NATIVE_FEED_URL` is empty in Debug).

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

What the host side still needs (owned by `Packages/NativeHost` and `native/Host`; see the hand-off in
the PR): `ShutdownParams.immediately` for Restart Host Now, sending the frozen shutdown on a protocol
mismatch before closing, `DurableHost.versionStatus` driving `HostVersionNotice`, and
`install-launch-agent.sh` reading `NATIVE_HOST_CHANNEL` so Nightly gets its own host.

## Configuration

Everything a release needs is in `Config/Shared.xcconfig`; the per-configuration files only pick
values. `Config/Native-Info.plist` is merged into the app's generated Info.plist.

| Setting | Meaning |
| --- | --- |
| `NATIVE_GITHUB_REPOSITORY` | `owner/name`. A placeholder until the repo exists; the app then says updates aren't set up, and `release.sh --publish` refuses to run |
| `NATIVE_BUNDLE_IDENTIFIER_BASE` | the app's bundle id; Nightly appends `.nightly`, the host helper `.Host` |
| `NATIVE_SPARKLE_PUBLIC_KEY` | Sparkle's EdDSA public key → `SUPublicEDKey` |
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
does everything. On a Mac without a Developer ID identity a dry run signs ad hoc and says so.

Each run: archives with `MARKETING_VERSION` and `CURRENT_PROJECT_VERSION` → copies the signed app
out of the archive → notarizes and staples it → zips it for Sparkle (`ditto`) and builds a signed,
notarized, stapled DMG for first installs → drafts notes → runs `generate_appcast` on the zip and
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

1. **Create the repository** on GitHub and set `NATIVE_GITHUB_REPOSITORY` in
   `Config/Shared.xcconfig`. Replace `NATIVE_BUNDLE_IDENTIFIER_BASE` with Native's real identifier
   (it can't change after release without breaking updates and settings).
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
7. **Nightly icon.** The icon owner adds the Nightly icon to the app target and sets
   `NATIVE_APP_ICON_NAME` in `Config/Nightly.xcconfig`.

## Testing updates locally

An update can be tested end to end without the Keychain or GitHub: a throwaway key file, two
builds and a local feed. Use a test bundle id so it never touches your own Native's settings or
host.

```sh
work=/tmp/native-update-test && mkdir -p $work/feed && cd $work
openssl genpkey -algorithm ed25519 -out key.pem
openssl pkey -in key.pem -outform DER | tail -c 32 | base64 > sparkle.key       # private seed
public=$(openssl pkey -in key.pem -pubout -outform DER | tail -c 32 | base64)
common=(--channel stable --no-dmg --ed-key-file $work/sparkle.key --download-url-prefix http://127.0.0.1:8765/
  --build-setting NATIVE_FEED_URL=http://127.0.0.1:8765/appcast.xml --build-setting NATIVE_SPARKLE_PUBLIC_KEY=$public
  --build-setting NATIVE_BUNDLE_IDENTIFIER_BASE=dev.native.updatetest)
scripts/release/release.sh "${common[@]}" --version 1.0.0 --build-number 1000 --output $work/old
scripts/release/release.sh "${common[@]}" --version 1.1.0 --build-number 1001 --output $work/new
cp $work/new/appcast/{appcast.xml,*.zip} $work/feed/
(cd $work/feed && python3 -m http.server 8765 --bind 127.0.0.1) &
ditto $work/old/Native.app $work/install/Native.app && open -n $work/install/Native.app
```

Then choose Native ▸ Check for Updates… and Update: the app downloads 1.1.0, verifies it, and
reopens as 1.1.0. Delete the test app and its defaults (`defaults delete dev.native.updatetest`)
afterwards.
