# Celebration download audit, 2026-10-24

Source revision: `a9f1ff11`. Public latest release: `v0.1.0` (index version `0.1.0`).
The app derives its base from `NativeGitHubRepository`; this release uses
`https://github.com/binbandit/native/releases/latest/download/`.
It requests `celebration-assets.json`, `celebration-assets.json.sig`, then the selected pack's
filename from the signed index. Each pack contains `stable`, `beta`, `nightly` and `dev`, each with
`light` and `dark` PNG entries. Halloween is bundled and downloads nothing. Julian Christmas
shares the Christmas pack; personal celebration artwork is forthcoming and downloads nothing.
All catalogue thumbnails are bundled. There are no third-party icon providers in this path.

All 44 pack requests returned HTTP 200 after two redirects, and every body matched the index's
SHA-256 and byte count. All 352 image entries decoded to Git LFS pointer text, with zero PNGs.
The release checkout had pointer files named `.png`; the pack script encoded and signed those
without materializing LFS objects or checking image bytes. The app's PNG validation rejects them
as incomplete. Downloads did not fail due to dead URLs, missing User-Agent, redirects, size limits
or managed policy. Before this fix, this feature did not enforce a download policy.

The files below all failed for that same reason. Links pin the audited release instead of `latest`.

| Edition / pack | HTTP | Image entries |
| --- | --- | --- |
| [ada-lovelace-day](https://github.com/binbandit/native/releases/download/v0.1.0/celebration-ada-lovelace-day.json) | 200 | 8 LFS pointers |
| [australia-day](https://github.com/binbandit/native/releases/download/v0.1.0/celebration-australia-day.json) | 200 | 8 LFS pointers |
| [australia-day-boxing-kangaroo](https://github.com/binbandit/native/releases/download/v0.1.0/celebration-australia-day-boxing-kangaroo.json) | 200 | 8 LFS pointers |
| [australia-day-reflection](https://github.com/binbandit/native/releases/download/v0.1.0/celebration-australia-day-reflection.json) | 200 | 8 LFS pointers |
| [australia-day-wattle](https://github.com/binbandit/native/releases/download/v0.1.0/celebration-australia-day-wattle.json) | 200 | 8 LFS pointers |
| [bandi-chhor-divas](https://github.com/binbandit/native/releases/download/v0.1.0/celebration-bandi-chhor-divas.json) | 200 | 8 LFS pointers |
| [carnival](https://github.com/binbandit/native/releases/download/v0.1.0/celebration-carnival.json) | 200 | 8 LFS pointers |
| [christmas](https://github.com/binbandit/native/releases/download/v0.1.0/celebration-christmas.json) | 200 | 8 LFS pointers |
| [chuseok](https://github.com/binbandit/native/releases/download/v0.1.0/celebration-chuseok.json) | 200 | 8 LFS pointers |
| [dia-de-muertos](https://github.com/binbandit/native/releases/download/v0.1.0/celebration-dia-de-muertos.json) | 200 | 8 LFS pointers |
| [dia-de-muertos-sugar-skull](https://github.com/binbandit/native/releases/download/v0.1.0/celebration-dia-de-muertos-sugar-skull.json) | 200 | 8 LFS pointers |
| [diwali](https://github.com/binbandit/native/releases/download/v0.1.0/celebration-diwali.json) | 200 | 8 LFS pointers |
| [earth-day](https://github.com/binbandit/native/releases/download/v0.1.0/celebration-earth-day.json) | 200 | 8 LFS pointers |
| [easter](https://github.com/binbandit/native/releases/download/v0.1.0/celebration-easter.json) | 200 | 8 LFS pointers |
| [eid-al-adha](https://github.com/binbandit/native/releases/download/v0.1.0/celebration-eid-al-adha.json) | 200 | 8 LFS pointers |
| [eid-al-fitr](https://github.com/binbandit/native/releases/download/v0.1.0/celebration-eid-al-fitr.json) | 200 | 8 LFS pointers |
| [guru-nanak-gurpurab](https://github.com/binbandit/native/releases/download/v0.1.0/celebration-guru-nanak-gurpurab.json) | 200 | 8 LFS pointers |
| [hanukkah](https://github.com/binbandit/native/releases/download/v0.1.0/celebration-hanukkah.json) | 200 | 8 LFS pointers |
| [holi](https://github.com/binbandit/native/releases/download/v0.1.0/celebration-holi.json) | 200 | 8 LFS pointers |
| [juneteenth](https://github.com/binbandit/native/releases/download/v0.1.0/celebration-juneteenth.json) | 200 | 8 LFS pointers |
| [kwanzaa](https://github.com/binbandit/native/releases/download/v0.1.0/celebration-kwanzaa.json) | 200 | 8 LFS pointers |
| [lantern-festival](https://github.com/binbandit/native/releases/download/v0.1.0/celebration-lantern-festival.json) | 200 | 8 LFS pointers |
| [matariki](https://github.com/binbandit/native/releases/download/v0.1.0/celebration-matariki.json) | 200 | 8 LFS pointers |
| [mathematics-day](https://github.com/binbandit/native/releases/download/v0.1.0/celebration-mathematics-day.json) | 200 | 8 LFS pointers |
| [meskel](https://github.com/binbandit/native/releases/download/v0.1.0/celebration-meskel.json) | 200 | 8 LFS pointers |
| [mid-autumn](https://github.com/binbandit/native/releases/download/v0.1.0/celebration-mid-autumn.json) | 200 | 8 LFS pointers |
| [new-year](https://github.com/binbandit/native/releases/download/v0.1.0/celebration-new-year.json) | 200 | 8 LFS pointers |
| [nowruz](https://github.com/binbandit/native/releases/download/v0.1.0/celebration-nowruz.json) | 200 | 8 LFS pointers |
| [orthodox-pascha](https://github.com/binbandit/native/releases/download/v0.1.0/celebration-orthodox-pascha.json) | 200 | 8 LFS pointers |
| [pride](https://github.com/binbandit/native/releases/download/v0.1.0/celebration-pride.json) | 200 | 8 LFS pointers |
| [programmers-day](https://github.com/binbandit/native/releases/download/v0.1.0/celebration-programmers-day.json) | 200 | 8 LFS pointers |
| [seollal](https://github.com/binbandit/native/releases/download/v0.1.0/celebration-seollal.json) | 200 | 8 LFS pointers |
| [songkran](https://github.com/binbandit/native/releases/download/v0.1.0/celebration-songkran.json) | 200 | 8 LFS pointers |
| [spring-festival](https://github.com/binbandit/native/releases/download/v0.1.0/celebration-spring-festival.json) | 200 | 8 LFS pointers |
| [st-patricks-day](https://github.com/binbandit/native/releases/download/v0.1.0/celebration-st-patricks-day.json) | 200 | 8 LFS pointers |
| [tet](https://github.com/binbandit/native/releases/download/v0.1.0/celebration-tet.json) | 200 | 8 LFS pointers |
| [tet-trung-thu](https://github.com/binbandit/native/releases/download/v0.1.0/celebration-tet-trung-thu.json) | 200 | 8 LFS pointers |
| [thanksgiving-canada](https://github.com/binbandit/native/releases/download/v0.1.0/celebration-thanksgiving-canada.json) | 200 | 8 LFS pointers |
| [thanksgiving-us](https://github.com/binbandit/native/releases/download/v0.1.0/celebration-thanksgiving-us.json) | 200 | 8 LFS pointers |
| [timkat](https://github.com/binbandit/native/releases/download/v0.1.0/celebration-timkat.json) | 200 | 8 LFS pointers |
| [us-independence-day](https://github.com/binbandit/native/releases/download/v0.1.0/celebration-us-independence-day.json) | 200 | 8 LFS pointers |
| [vaisakhi](https://github.com/binbandit/native/releases/download/v0.1.0/celebration-vaisakhi.json) | 200 | 8 LFS pointers |
| [valentines-day](https://github.com/binbandit/native/releases/download/v0.1.0/celebration-valentines-day.json) | 200 | 8 LFS pointers |
| [vesak](https://github.com/binbandit/native/releases/download/v0.1.0/celebration-vesak.json) | 200 | 8 LFS pointers |

## Reproduction and verification

- Download the index and each listed pack with `curl -fLsS`. Decode each `images` value as base64
  and compare its first bytes with the PNG signature. Every audited entry instead starts with
  `version https://git-lfs.github.com/spec/v1`.
- The captured Valentine's Day pack is a regression fixture in `Packages/AppAppearance`. It is
  re-signed with a throwaway key in tests, rejected without caching, then replaced by real PNG
  data to verify Retry reloads the index and caches all eight images.
- `test_celebration_assets.py` runs the actual pack command in temporary repositories with a
  local LFS remote. Against the original script, pointer checkout, missing LFS and invalid-image
  tests fail; against the fix, they pass. No release credentials are used.
- Download model tests cover managed disable with zero requests, disabling in flight, cached
  artwork under disabled policy, offline fallback, and suppression of automatic retry loops.
- Regenerating the full catalogue with a throwaway signer produced 44 packs containing 352 PNGs;
  every generated pack matched its index hash and size.
- Visual check pending on the main Mac: enable a celebration, test successful, offline and
  policy-disabled downloads in light and dark. elara has no Accessibility or Screen Recording
  permission. Use the isolated Debug override recipe in `celebrations-artwork.md` so repository
  artwork does not bypass the downloader. No screenshots were captured on elara.
