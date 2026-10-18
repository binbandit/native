# Celebration artwork: what the icon work delivers

The Celebrations plugin (`docs/celebrations.md`, `native/Celebrations/`) applies a celebration's app
icon only when its icon set is complete: four build channels, each in light and dark. Until then the
catalogue shows "Artwork forthcoming" and only Home changes. This file is the hand-off from the
plugin to the icon work: the files each edition needs, where they go, and how an edition is switched
on once they exist. The plugin never creates or edits icon artwork.

## Día de Muertos (needed now)

Icon set `native.dia-de-muertos`, used by the celebration `native.dia-de-muertos` (1 and 2
November, optional 28 October to 3 November). Its Home edition already ships
(`native/DesignSystem/Brand/NativeMuertosMark.swift`); the icon is the missing half.

### Sources

Icon Composer documents, one per channel, beside the drafts already in progress:

```
design/app-icon/celebrations/dia-de-muertos/stable.icon
design/app-icon/celebrations/dia-de-muertos/beta.icon
design/app-icon/celebrations/dia-de-muertos/nightly.icon
design/app-icon/celebrations/dia-de-muertos/dev.icon
```

### Compiled images (eight)

The Mac applies a celebration icon at runtime (`NSApplication.applicationIconImage`), so each
channel and appearance is one flattened image in the asset catalog, named exactly like Halloween's:

| Channel | Light | Dark |
| --- | --- | --- |
| Regular (`stable`) | `AppIcon-dia-de-muertos-stable-light` | `AppIcon-dia-de-muertos-stable-dark` |
| Beta (`beta`) | `AppIcon-dia-de-muertos-beta-light` | `AppIcon-dia-de-muertos-beta-dark` |
| Nightly (`nightly`) | `AppIcon-dia-de-muertos-nightly-light` | `AppIcon-dia-de-muertos-nightly-dark` |
| Dev (`dev`) | `AppIcon-dia-de-muertos-dev-light` | `AppIcon-dia-de-muertos-dev-dark` |

Each is `native/Assets.xcassets/<name>.imageset/` holding `icon.png` and the same `Contents.json` as
`AppIcon-halloween-stable-light.imageset` (one universal image). `icon.png` is 1024×1024, sRGB, RGBA,
rendered from the `.icon` document with the macOS icon shape, its margins transparent and its own
shadow, exactly as the Halloween images are, so the Dock shows it at the same size as the compiled
icon.

### What each must keep

- The Native interlock recognisable at Dock sizes; check 16, 32, 64 and 128 points in light and dark
  (a `dock-sizes.png` preview like Halloween's).
- Regular: the warm celebration palette. Beta: its β cue. Nightly: large, high-contrast stars that
  no marigold, paper edge or flame covers. Dev: its code and blueprint character.
- Light and dark as real pairs, not one image darkened. Clear and Tinted can't be carried by runtime
  images (`PlatformAppIcon`); keep their previews for review, but only the eight images above ship.
- Original artwork, reviewed for the celebration's meaning: remembrance and affection, cempasúchil,
  candlelight and papel picado. Two drafts exist (`dia-de-muertos`, `dia-de-muertos-sugar-skull`);
  choosing one is Brayden's call with that review, and the Home edition can take the chosen icon's
  palette afterwards (`NativeMuertosEdition`).

### Switching the icon on

When all eight images are in the asset catalog, in one change:

1. In `Packages/AppAppearance/Sources/AppAppearance/Celebrations/FirstPartyCelebrations.swift`,
   replace `icons: .forthcoming` in `diaDeMuertosIcons` with the channel images, as Halloween does:

   ```swift
   icons: .channels(
       Dictionary(
           uniqueKeysWithValues: AppIconVariant.allCases.map { variant in
               let name = "AppIcon-dia-de-muertos-\(variant.rawValue)"
               return (variant, IconSetImagePair(light: .asset("\(name)-light"), dark: .asset("\(name)-dark")))
           })),
   ```

2. In `Packages/AppAppearance/Tests/AppAppearanceTests`, expect `muertos.appIcon == .ready` in
   `firstPartyCatalogueIsValid`, and in `halloweenAndMuertosOverlap` expect the icon to follow
   Día de Muertos on 1 and 2 November (`appliesToAppIcon == true`). Run `swift test`.
3. Check the running app: `scripts/dev/run-isolated.sh celebrations -- -nativeDate 2026-11-01` with
   Halloween and Día de Muertos on shows the Día de Muertos icon in the Dock and on Home; a build
   missing any one image keeps the icon as it was and Settings ▸ Celebrations names the missing file.

## Every later edition

The same shape, by the edition's slug (the celebration id without `native.`): sources in
`design/app-icon/celebrations/<slug>/{stable,beta,nightly,dev}.icon`, images
`AppIcon-<slug>-<channel>-<light|dark>`, and an icon set `native.<slug>` in `FirstPartyCelebrations`.
An edition without all eight images stays "forthcoming" and never applies its icon.
