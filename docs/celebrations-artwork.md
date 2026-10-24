# Celebration artwork: what the icon work delivers, and how it ships

The Celebrations plugin (`docs/celebrations.md`, `native/Celebrations/`) applies a celebration's app
icon only when its icon set is complete: four build channels (Regular `stable`, `beta`, `nightly`,
`dev`), each in light and dark. Until then the icon stays as it is and only Home can change. This is
the hand-off between the icon work, which owns the artwork, and the plugin, which never creates or
edits it.

## What the icon work delivers

Per edition, in `design/app-icon/celebrations/<edition>/` (the edition is the celebration id
without `native.`, such as `valentines-day`):

- `{stable,beta,nightly,dev}.icon`: the Icon Composer sources.
- `{stable,beta,nightly,dev}-{light,dark}.png`: eight flattened renders, 1024×1024 sRGB RGBA, with
  the macOS icon shape, transparent margins and its own shadow, like the Halloween images. These are
  what the Mac applies at runtime (`NSApplication.applicationIconImage`), so they must look right at
  Dock sizes (16 to 128 points) in both appearances.
- Clear and Tinted previews for review only: runtime images can't carry those appearances.

Every channel keeps its cue: Nightly's large, high-contrast stars uncovered, Beta's β, Dev's code
and blueprint character. Artwork is original and reviewed for the celebration's meaning.

## How it ships

Bundling every edition would add over 100 MB, so only Halloween's icons are compiled into the app.
The rest ship in two parts, both built by `scripts/release/celebration-assets.sh` from the folder
above:

1. **Thumbnails, bundled.** `celebration-assets.sh thumbnails` renders each edition's Regular light
   and dark icon at 128 px into `native/Celebrations/CelebrationThumbnails.xcassets`
   (`CelebrationThumbnail-<edition>-<light|dark>`), about 1.5 MB in all, so the catalogue previews
   work offline. Re-run it when artwork changes and commit the result.
2. **Packs, downloaded.** `celebration-assets.sh pack <dir>` writes `celebration-<edition>.json` (the
   eight PNGs) per edition, the index `celebration-assets.json` (each pack's SHA-256 and size) and
   `celebration-assets.json.sig`, the index's Ed25519 signature made with the update key. The release
   workflow uploads them beside the app. Native fetches an edition's pack from the latest release
   when someone chooses it (or a week before its dates, if it was chosen earlier), checks the index
   signature with `SUPublicEDKey` and the pack against the index, and caches it in Application
   Support per bundle id. Offline or failed downloads keep the base icon; the chooser says
   "Downloads when you're online" or shows the error with Retry.

The pack command materializes Git LFS renders from the repository's configured LFS remote when
needed, then rejects non-PNG input before signing. A pointer-only checkout must never publish a
signed pack. Run `python3 -m unittest discover -s scripts/release/tests -p test_celebration_assets.py -v`
to exercise real, local LFS remotes, missing objects and invalid artwork without release credentials.

All runtime requests (index, signature and packs) go through `CelebrationAssetDownloads` in
`Packages/AppAppearance`, configured by `CelebrationAssetStore`. The default base is the latest
release under `NativeGitHubRepository`. Managed `policy.celebrations.downloadsEnabled = false`
prevents all three requests, cancels in-flight downloads and keeps bundled or cached artwork usable.
Managed `policy.celebrations.baseURL` selects an HTTP(S) mirror containing the same Native-signed
index and packs. It does not change the trusted key or fall back to the public server when a mirror
is unavailable. These keys also work as ordinary preferences when not managed.

Offline, missing or rejected packs keep the base icon and bundled catalogue thumbnail. The chooser
shows a quiet explanation and Retry for a failed download. Automatic refresh does not immediately
retry a failed pack; Retry, selecting it again or restarting Native permits another attempt. Retry
reloads the signed index, so repaired release assets can be used without restarting the app.

The [2026-10-24 download audit](celebration-download-audit.md) lists every pack and the reproduced
packaging failure. After this fix lands, a release maintainer must publish regenerated packs and
their signed index through the normal release process; existing v0.1.0 assets remain broken until
replaced or superseded. No update keys or published release assets are changed by this fix.

An edition is in a pack once its folder has all eight PNGs; the script names any that are
incomplete. Its icon set in `FirstPartyCelebrations` uses `icons: .pack("<edition>")` and its
thumbnail; the catalogue entry exists already for every edition in `docs/celebrations.md`.

## Día de Muertos

Both drafts ship as styles of the one celebration: the painted interlock
(`design/app-icon/celebrations/dia-de-muertos/`, icon set `native.dia-de-muertos`) is the default,
and the sugar skull (`dia-de-muertos-sugar-skull/`, icon set `native.dia-de-muertos-sugar-skull`) is
an alternate the user picks under Style in Settings ▸ Celebrations, captioned as not keeping the
interlock. Each is its own pack with its own thumbnail, and only the chosen style downloads. Home
uses the design system's edition (`NativeMuertosMark`) for both.

## Checking packs locally

Never with the real key. Make a throwaway Ed25519 key, sign a local pack with it, serve it, and point
a Debug build at it (only Debug reads these overrides):

```sh
CELEBRATION_ASSETS_SIGN=/path/to/throwaway-signer scripts/release/celebration-assets.sh pack /tmp/packs
(cd /tmp/packs && python3 -m http.server 8765)
scripts/dev/run-isolated.sh celebrations -- -celebrationAssetsURL http://127.0.0.1:8765/ \
    -celebrationAssetsKey <throwaway public key, base64>
```
