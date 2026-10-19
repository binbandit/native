# App size

Every update is a download, and Native updates often, so its size is a cost users pay again and
again. This document is the budget, how it's enforced, where the bytes go, and what's left to cut.
It belongs with `docs/performance.md`.

## Budgets

MB here are 10^6 bytes, as Finder counts them. "Installed" is the bytes in the app bundle;
"download" is Sparkle's update archive (what every update fetches) and the disk image (a first
install). The budgets sit about 10% above where the app was when they were set, so growth gets
noticed while there's still room to choose what to cut; lower them as the cuts in "Still to do" land.

| What | Budget | 2026-10-19 |
| --- | --- | --- |
| Download, update archive | 48 MB | 43.3 MB |
| Download, disk image | 49 MB | 43.9 MB |
| Installed app | 128 MB | 116.4 MB |
| App binary (`Contents/MacOS/Native`) | 68 MB | 62.1 MB |
| Script runtime (`Contents/Helpers/native-script-runtime`) | 42 MB | 41.4 MB |

`scripts/release/size-check.sh` holds the same numbers and fails when anything is over:

- `scripts/release/check.sh` (every pull request, through `check.yml`) builds Release and Nightly and
  checks both apps. It compresses each one the way a release packs its update archive, so the
  download is measured without a release. CI has no Zig, so its builds have no terminal and come in
  about 12 MB under a release; the script says so when that's the case.
- `scripts/release/release.sh` checks the app, update archive and disk image it's about to publish,
  dry runs included, and stops before publishing when they're over.

Raise a budget only with the reason written here, in the same change.

## Measuring

```sh
scripts/release/size-check.sh <Native.app>                    # any build: sizes against the budget
scripts/release/release.sh --channel stable --version 0.0.1    # a dry run: the real archive, zip and DMG
```

To see where the app binary's bytes come from, have the linker write a map and sum it:

```sh
scripts/release/release.sh --channel stable --version 0.0.1 --build-setting LD_GENERATE_MAP_FILE=YES
python3 -I scripts/release/linkmap.py "$TMPDIR/native-release/stable/DerivedData/Build/Intermediates.noindex/ArchiveIntermediates/native/IntermediateBuildFilesPath/native.build/Release/native.build/Native-LinkMap-normal-arm64.txt"
```

`linkmap.py` totals every symbol by library (`libghostty.a`, `Sentry.framework`), Swift package
module, or folder of the app's own code (`native/Views`), split into code (`__text`) and constant
data (`__const`). For the script runtime, relink it with a map in a copy of its cargo target folder:
`cargo rustc --release --bin native-script-runtime -- -C link-arg=-Wl,-map,<file> -C strip=none`.

## Where the bytes go

2026-10-19, a stable release dry run (`release.sh`, arm64, Developer ID-style archive signed ad hoc).

| Part | Installed | In the download |
| --- | --- | --- |
| App binary | 62.1 MB | 19.0 MB |
| Script runtime (V8) | 41.4 MB | 15.0 MB |
| `Assets.car` (app icons) | 6.8 MB | 6.6 MB |
| Host helper (`Native Host.app`) | 2.7 MB | 1.1 MB |
| Frameworks (Sparkle, Sentry's loader) | 2.7 MB | 1.0 MB |
| Everything else | 0.7 MB | 0.6 MB |
| **Total** | **116.4 MB** | **43.3 MB** |

Code compresses about threefold and tree-sitter's parse tables about tenfold, but the icons are PNGs
that don't compress at all, so `Assets.car` costs nearly as much to download as to install.

### The app binary

The top 25 of the link map, in MB. "Code" is `__TEXT,__text`, "const" is `__TEXT,__const`, "all"
adds Swift metadata, unwind tables and data.

| From | Code | Const | All |
| --- | --- | --- | --- |
| libghostty.a | 6.60 | 4.31 | 12.39 |
| package TreeSitterSwift | 0.39 | 3.75 | 4.18 |
| package TreeSitterKotlin | 0.15 | 3.89 | 4.05 |
| package TreeSitterCPP | 0.13 | 3.28 | 3.43 |
| native/Views | 1.96 | 0.06 | 2.47 |
| package TreeSitterRuby | 0.07 | 2.03 | 2.10 |
| Sentry.framework (linked statically) | 1.10 | 0.04 | 1.95 |
| native/DesignSystem | 1.37 | 0.05 | 1.74 |
| native/GitHub | 1.24 | 0.04 | 1.59 |
| package TreeSitterTSX | 0.03 | 1.40 | 1.43 |
| package TreeSitterTypeScript | 0.02 | 1.38 | 1.41 |
| package TreeSitterBash | 0.18 | 1.17 | 1.36 |
| package TreeSitterRust | 0.02 | 1.08 | 1.10 |
| package GitHub | 0.75 | 0.05 | 1.06 |
| package ACP | 0.62 | 0.04 | 0.86 |
| native/Models | 0.70 | 0.02 | 0.83 |
| native/Git | 0.61 | 0.02 | 0.79 |
| package NativeAutomation | 0.53 | 0.04 | 0.74 |
| native/Automation | 0.57 | 0.02 | 0.74 |
| native/Usage | 0.59 | 0.02 | 0.72 |
| native/MCP | 0.57 | 0.01 | 0.70 |
| package TreeSitterC | 0.07 | 0.55 | 0.63 |
| package NativeExpeditions | 0.48 | 0.03 | 0.62 |
| native/Expeditions | 0.51 | 0.01 | 0.62 |
| package Git | 0.53 | 0.01 | 0.62 |
| **Whole binary** | **28.54** | **25.64** | **61.93** |

By kind:

- **Tree-sitter grammars, 22.2 MB.** Almost all parse tables (`__const`), which compress about
  tenfold, so they cost about 2.3 MB of download. Kotlin, C++ and Ruby alone are 9.6 MB.
- **The app's own code (`native/`), 16.4 MB, and Native's Swift packages, about 8 MB.** No single
  feature stands out; Views, DesignSystem and GitHub are the largest.
- **libghostty, 12.4 MB.** Ghostty's Zig core is 7.1 MB, of which 3.05 MB are fonts it embeds and
  always loads as fallbacks: Symbols Nerd Font (2.44 MB, the icons in prompts like Starship's) and
  JetBrains Mono regular and italic (0.61 MB). glslang and SPIRV-Cross, which compile custom
  shaders, are 3.5 MB; FreeType 0.6 MB, oniguruma (link matching) 0.5 MB, the image decoders
  0.25 MB, Dear ImGui (the terminal inspector) 0.25 MB, libpng and zlib 0.13 MB. Ghostty's build
  has no option to leave any of these out.
- **Sentry, 1.95 MB.**
- Nothing is generated data compiled as code: the biggest Swift `__const` is 0.06 MB.

### The script runtime

V8 through rusty_v8's prebuilt library (150.4.0, pointer compression), 41.4 MB stripped:

| Part | MB |
| --- | --- |
| ICU data, embedded (`icudtl.dat`) | 10.82 |
| Turboshaft and TurboFan, the optimizing compilers | 8.04 |
| Maglev, the mid-tier compiler | 3.18 |
| Embedded builtins | 2.11 |
| WebAssembly | 1.71 |
| ICU code | 1.52 |
| Ignition, Sparkplug and the rest of V8 | about 9 |
| Rust: the runtime, std, serde, Temporal and ICU4X | about 1 |

The runtime runs V8 with `--jitless`, so the 13 MB of compilers and WebAssembly are never used, and
nothing in it calls `Intl`. "The script runtime: V8 or JavaScriptCore" below weighs what to do.

## What changed

| | Before | After |
| --- | --- | --- |
| `just install` (a plain Release build): installed | 152.8 MB | AFTER_INSTALL |
| `just install`: app binary / host helper | 95.3 MB / 5.9 MB | AFTER_BINARY |
| `just install`: what it would cost to download | 47.5 MB | AFTER_DOWNLOAD |
| A release: installed / update archive / disk image | 116.4 / 43.3 / 43.9 MB | unchanged |

- **Local builds strip like releases.** Archives already stripped (`DEPLOYMENT_POSTPROCESSING` is on
  for the install action), but a plain Release build, which is what `just install` makes, didn't,
  so the app it installed carried 229,000 symbols and 36 MB more than users get. `Config/Release.xcconfig`
  (and so Nightly) now sets `DEPLOYMENT_POSTPROCESSING`, `STRIP_INSTALLED_PRODUCT` and
  `STRIP_STYLE = all` for every Release and Nightly build. dSYMs are still made first, so Sentry
  symbolication is unchanged.
- **The budget is enforced** (above), so the next 10 MB shows up in the pull request that adds it.

## The script runtime: V8 or JavaScriptCore

The runtime is 35% of every download. `docs/script-runtime.md` chose V8 because JavaScriptCore's
public API has no heap limit and no way to stop a running script from another thread, and because
in-process JavaScriptCore would put untrusted code inside the app.

V8_SECTION

## Still to do

| What | Saves | Owner |
| --- | --- | --- |
| STILL_TO_DO | | |
