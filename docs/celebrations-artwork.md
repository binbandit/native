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

An edition is in a pack once its folder has all eight PNGs; the script names any that are
incomplete. Its icon set in `FirstPartyCelebrations` uses `icons: .pack("<edition>")` and its
thumbnail; the catalogue entry exists already for every edition in `docs/celebrations.md`.

## Día de Muertos (waiting on a choice)

Two drafts exist: `dia-de-muertos` (painted floral links) and `dia-de-muertos-sugar-skull`. Brayden
chooses, with cultural review; both are in the script's `PENDING` list until then. To switch it on:

1. Keep the chosen draft as `design/app-icon/celebrations/dia-de-muertos/` and remove both names
   from `PENDING` in `scripts/release/celebration-assets.sh` (drop the unchosen folder or leave it
   pending).
2. Re-run `celebration-assets.sh thumbnails`.
3. In `FirstPartyCelebrations.diaDeMuertosIcons`, replace `icons: .forthcoming` with
   `icons: .pack("dia-de-muertos")` and add its `thumbnail`, as the catalogue editions do.
4. In the AppAppearance tests, expect `muertos.appIcon == .downloadable(.notDownloaded)` in
   `firstPartyCatalogueIsValid`; run `swift test`.
5. Check a release-built pack, or a local one (below), with
   `scripts/dev/run-isolated.sh celebrations -- -nativeDate 2026-11-01`.

The Home edition (`NativeMuertosMark`) ships already and can take the chosen icon's palette.

## Checking packs locally

Never with the real key. Make a throwaway Ed25519 key, sign a local pack with it, serve it, and point
a Debug build at it (only Debug reads these overrides):

```sh
CELEBRATION_ASSETS_SIGN=/path/to/throwaway-signer scripts/release/celebration-assets.sh pack /tmp/packs
(cd /tmp/packs && python3 -m http.server 8765)
scripts/dev/run-isolated.sh celebrations -- -celebrationAssetsURL http://127.0.0.1:8765/ \
    -celebrationAssetsKey <throwaway public key, base64>
```
