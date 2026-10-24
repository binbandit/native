# App size

Every update is a download, and Native updates often, so its size is a cost users pay again and
again. This document is the budget, how it's enforced, where the bytes go, and what's left to cut.
It belongs with `docs/performance.md`.

## Budgets

MB here are 10^6 bytes, as Finder counts them. "Installed" is the bytes in the app bundle;
"download" is Sparkle's update archive (what every update fetches) and the disk image (a first
install rehearsal). Public releases now attach only the ZIP for both first installs and updates;
the DMG still builds locally with the existing signing, notarization and size checks. The asset
inventory and retention limits are in `docs/releasing.md`. This changes file count, not the app
bundle or its size budgets. The budgets sit about 10% above where the app was when they were set,
so growth gets noticed while there's still room to choose what to cut; lower them as the cuts in "Still to do" land.

| What | Budget | 2026-10-24, after the cold-package and gallery cut |
| --- | --- | --- |
| Download, update archive | 47.5 MB | 46.8 MB |
| Download, disk image | 48 MB | not remeasured |
| Installed app | 118 MB | 116.4 MB |
| App binary (`Contents/MacOS/Native`) | 70 MB | 59.6 MB |
| Script runtime (`Contents/Helpers/native-script-runtime`) | 42 MB | 41.4 MB |

`scripts/release/size-check.sh` holds the same numbers and fails when anything is over. It also
fails an app without the terminal (libghostty in the binary, Ghostty's terminfo and shell
integration in its resources) or the script runtime: Xcode's build phases only warn when they can't
build them, and such an app looks 12 to 40 MB smaller than what ships.

- `scripts/release/check.sh` (every pull request, through `check.yml`) builds the terminal and the
  script runtime, then Release and Nightly, and checks both apps. It compresses each one the way a
  release packs its update archive, so the download is measured without a release.
- `scripts/release/release.sh` checks the app, update archive and disk image it's about to publish,
  dry runs included, and stops before publishing when they're over.

Raise a budget only with the reason written here, in the same change.

2026-10-24: the collapsed sidebar attention list integrated with main through `44feb957` at
`a69f9095` measures 47.1 MB for the Release update archive and 47.2 MB for Nightly, over the
47 MB download allowance. The shared rows, Peek and command focus routing add compiled code
without bundled assets or dependencies; fixtures remain Debug-only. The download budget is
47.5 MB for this integration, with a small margin. Installed apps remain 117.0/117.1 MB and
both app binaries are 60.0 MB, within their unchanged budgets. These are integrated measurements,
not an isolated feature delta. Remeasure when the gated redesign replaces its legacy views.

2026-10-24: Fine print's resting field and merged settings popover keep the existing composer
available behind the default-off switch. The integrated local build at `ffb4c380` measures
47.1 MB downloaded for Release and 47.2 MB for Nightly, with installed sizes of 117.0 and
117.1 MB and binaries of 60.0 and 60.1 MB. Main at `1262168a` measured 46.8 and 46.9 MB
in [CI](https://github.com/binbandit/native/actions/runs/40082622708). These are integrated
build measurements, not an isolated binary delta. This slice adds no bundled assets or
dependencies. The update archive allowance is 47.5 MB for this integration; the installed,
binary, runtime and disk-image limits stay unchanged. Remeasure when Fine print replaces
the legacy composer and the temporary duplication can be removed.

2026-10-23: the reviewed Change Agent flow adds about 0.1 MB to the app binary, taking Release
from main's 57.9 MB to just over 58 MB. Its local handoff generation, review controls and task
continuity add no dependencies or assets. The binary budget is now 58.5 MB to accommodate that
feature with a small margin. The installed app (114.6 MB) and update archive (45.7 MB) remain
within their unchanged budgets.

On the same day, the task artifact viewer raised the Nightly app binary from 57.9 MB on
`7e98b62a` to 58.0 MB on `d242798c` (CI reports one decimal place). This adds the shared image
canvas, native document preview adapters and preservation of image/file content from agent and
tool messages, with no bundled assets or dependencies. It uses the same 58.5 MB binary allowance.
At `d242798c`, the measured download was 45.8 MB and installed app was 114.8 MB, within their
unchanged limits.

2026-10-23: Fine print's annotated approval, command analysis and deliberate-confirmation controls
bring the integrated Nightly binary to 58.7 MB at `c19a6495` (PR #97, Check Nightly job
120414607392). The old quiet-settings-line implementation is removed; this slice adds no bundled
assets or third-party dependencies. The binary allowance is 59 MB for this shared component and
its platform key routing. The measured update archive (46.1 MB) and installed app (115.5 MB) remain
within their unchanged limits. These are integrated build measurements, not an isolated size delta.

Home Next's inline questions, plan review and failure recovery add about 0.1 MB of compiled UI
and model code. Nightly measured 58.4 MB on base `638e0771` and just over 58.5 MB on `2b6cfdb9`
with this slice. The download stays at 46.0 MB and the installed app rises from 115.1 MB to 115.3 MB, within their
unchanged budgets. The slice reuses the composer and error components and adds no dependencies
or bundled assets. `NativeHomeNext` remains off by default; remove the old Home presentation
when Next is complete, then remeasure its temporary duplication.

Measurements: [base Nightly](https://github.com/binbandit/native/actions/runs/39949712258/job/120400913612)
and [Home Next Nightly](https://github.com/binbandit/native/actions/runs/39952262729/job/120409343802).

2026-10-24: the integrated worktree-creation commands and Plainly Settings build at `dde394e1`
measures 58.6 MB for the Nightly binary, 46.1 MB downloaded and 115.4 MB installed. Earlier
feature measurements used separate branches; their combined code now exceeds the 58.5 MB
binary allowance. Creation hooks, captured terminal logs and their retry controls add no assets
or dependencies. The binary budget is now 59 MB for this measured integration, with a small
margin. The download, installed, disk-image and script-runtime budgets stay unchanged.

The task well integrated with current main at `a050243f` measures 59.026 MB for both Release
and Nightly binaries, about 0.026 MB above that allowance. The default-off toolbar, tool list
and child-question handoff compile alongside the existing task screen, with no added assets
or dependencies; their fixtures remain Debug-only. The binary budget is now 59.5 MB for this
integration. Nightly downloads at 46.3 MB and installs at 115.8 MB, within the unchanged limits.
Remeasure when the well replaces the legacy task presentation.

Quick Entry adds the opt-in panel, context capture, address pickers and background-start
confirmation, reusing the existing editor and task pipeline without assets or dependencies.
With main through `638e0771`, its Nightly binary at `00eef888` measured 58.61 MB, about 0.6 MB
above the artifact-viewer baseline above. That feature measurement used a 59 MB binary allowance;
the measured 46.3 MB update archive and 115.3 MB installed app remain within unchanged budgets.

2026-10-24: Quick Entry integrated with main through `a9f1ff11` at `bf3c0b49` measures 59.1 MB
for both Release and Nightly binaries, exceeding the shared 59 MB allowance. This combines the
opt-in panel with the worktree setup, Settings and task Peek changes already on main. The binary
budget is now 59.5 MB, with a small margin for this measured integration. The largest update
archive (46.3 MB) and installed app (115.8 MB) remain within their unchanged budgets; no assets
or dependencies were added.

Fine print integrated with Home Next and main through `db0f3012` at `408ba425` measures
59.560 MB for both Release and Nightly binaries, about 0.060 MB above the 59.5 MB allowance.
The annotated approvals, command analysis and deliberate confirmation compile alongside the
new Home questions, plan review and recovery code, with no added assets or dependencies. The
binary budget is now 60 MB for this measured integration. Downloads remain 46.4/46.5 MB and
installed apps 116.2/116.3 MB, within their unchanged limits. Remeasure when the gated redesign
components replace their legacy presentations.

2026-10-24: approved by Brayden, the app binary budget is now 70 MB to give a little room for
growth. Growth since the budgets were set at a 53.2 MB binary is mostly the redesign compiling
old and new versions of six areas behind switches. Reclaim that space by deleting each old
version when its switch flips. The size cut below brings the executable under the former 60 MB
limit. The download, disk-image, installed-app and script-runtime budgets are unchanged.

## 2026-10-24: recover headroom by cutting size

Measured arm64 Release builds with Xcode 27.1 (27A9275), without signing or launching them,
in the same `/tmp/native-dd/app-size` folder. The historical build is `d2cfc5aa`, the last
commit on October 21 in Melbourne. The October 24 baseline is `7347ad34`, including sidebar
PR #90 and the celebration screens in #104. This is a controlled comparison on that base.
The pinned terminal and script runtime are identical in all three builds. This cut does not alter the budgets. PR #116 separately raised
the executable allowance to 70 MB while the work was underway; the results below also pass
the original 60 MB gate from `0cb6f62d`.

| Component, MB on disk | October 21 | October 24 before | After |
| --- | ---: | ---: | ---: |
| Main executable | 57.192 | 60.253 | 59.550 |
| Script runtime | 41.373 | 41.373 | 41.373 |
| Host helper bundle | 4.987 | 5.270 | 5.270 |
| Frameworks | 2.781 | 2.781 | 2.781 |
| Resources | 7.344 | 7.345 | 7.345 |
| Other bundle files | 0.003 | 0.003 | 0.003 |
| **Installed total** | **113.679** | **117.025** | **116.322** |
| Update archive, rounded by `size-check.sh` | 45.5 | 47.0 | 46.8 |

The executable falls by 702,896 bytes, leaving 449,592 bytes below 60 MB with #90 already
included. Earlier builds measured #90 itself at 50,592 bytes, from `74353da1` to `0cb6f62d`.
The preceding main at `74353da1` was 59.951 MB, only 49 KB below the limit.

Final integration through #100 (`3c0d9258`) measures 59.618 MB for Release and 59.618 MB
for Nightly. Release installs at 116.390 MB; the update archives are 46.8 and 46.9 MB. Both
pass the original 60 MB script as well as the current policy checks. The controlled table
above isolates this cut from the later Undo presentation changes.

### What grew

From October 21 to `7347ad34`, the executable grew 3.062 MB and the host helper 0.283 MB. Assets, frameworks
and V8 were effectively unchanged. The largest increases attributed by the link map are Home
Next (0.273 MB), Settings (0.205), Quick Entry/NewTask (0.190), task Peek (0.170), approvals
(0.161), DesignSystem (0.162), Hosts (0.143), GitHub views (0.140), SessionTools (0.119), and
Artifacts (0.109). This is accumulated feature code, including presentations behind switches.

The largest unchanged dependencies are libghostty (12.394 MB), TreeSitterSwift (4.178),
TreeSitterTSX (1.433), TreeSitterTypeScript (1.406), TreeSitterBash (1.363), and TreeSitterRust
(1.104). The app's largest folders before this cut are Views (3.178 MB), DesignSystem (2.027),
GitHub (1.822), and Models (1.277). Link-map attribution includes zero-fill data and shared
symbols, so it is not an exact partition of the executable's file bytes.

The largest individual symbols are Swift's tree-sitter parse table (2.677 MB), Ghostty's
embedded Symbols Nerd Font (2.440), TSX's parse table (0.917), TypeScript's parse table
(0.897), Swift's small parse table (0.787), and Rust's parse table (0.747). The largest Swift
function is the celebration catalogue initializer, only 0.031 MB. Rewriting that catalogue
would not address the main source of growth.

Swift metadata sections total 2.521 MB before and 2.492 MB after, including type references
(1.664 to 1.638 MB) and reflection names (0.143 MB). Named function-specialization symbols
account for about 1.81 MB before and 1.77 MB after. Reflection remains enabled; dead stripping,
whole-module optimization, and stripping the shipped executable were already enabled.

### What was cut

Seven packages now use Swift's `-Osize` in release configurations. They perform workflow
decisions, preference/catalogue work, or operations dominated by disk, subprocess or network
I/O. The app, ACP, host protocol, transcript, Markdown and diff renderer retain `-O`.
Debug optimization is unchanged. These are local package target flags, not a global override.

| Link-map contribution, MB | Before | After |
| --- | ---: | ---: |
| Git | 0.725 | 0.566 |
| GitHub | 1.103 | 1.006 |
| NativeAutomation | 0.745 | 0.678 |
| NativeExpeditions | 0.622 | 0.557 |
| AppAppearance | 0.577 | 0.498 |
| MCPClient | 0.522 | 0.474 |
| Skills | 0.311 | 0.284 |
| App DesignSystem | 2.027 | 1.840 |

The design gallery has no entry point in the shipping app, but its public SwiftUI conformances
kept it and its sample screens linked. Its eight view files and the three component previews
that reference them now sit under `#if DEBUG`. Shared preview fixtures remain available for
other preview bodies to type-check; without the gallery, they strip out. The gallery is still
built in Debug.
No feature, asset, protocol, or dependency was removed.

### Asset and runtime audit

`Assets.car` is 6.779 MB in every measured Release build (6.847 MB in Nightly). Its catalogues contain alternate/channel
icons and 88 celebration thumbnail renditions at 128 by 128 pixels. The thumbnail PNG sources
total 1.231 MB before asset-catalog compilation; `assetutil` rendition sizes do not include all
shared pixel storage. The full celebration packs from #109 are downloaded on demand, not
embedded. There are no byte-identical duplicate PNGs in either bundled catalogue. The two
bundled Geist fonts total 0.287 MB, and there are no bundled sound files. Larger celebration
artwork under `design/` is not an app resource.

V8 remains 41.373 MB, and the framework payload remains 2.781 MB. Ghostty still embeds its
3.05 MB of fallback fonts and supports custom shaders. Removing those, replacing grammars
with lexers, or changing the script engine would change existing behavior. Channel-specific
icon catalogues remain a separate opportunity below. The safe cuts here target compiled code.

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

2026-10-19, before Kotlin, C++ and Ruby went back to the lexer (below), from a stable release dry run (`release.sh` on a Mac without a Developer ID, so signed ad hoc).

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
  tenfold, so they cost about 2.3 MB of download. Kotlin, C++ and Ruby were 9.6 MB of them, and
  are lexed now.
- **The app's own code (`native/`), 16.4 MB, and Native's Swift packages, about 8.5 MB.** No
  single feature stands out; Views, DesignSystem and GitHub are the largest.
- **libghostty, 12.4 MB.** Ghostty's Zig core is 7.1 MB, of which 3.05 MB are fonts it embeds and
  always loads as fallbacks: Symbols Nerd Font (2.44 MB, the icons in prompts like Starship's) and
  JetBrains Mono regular and italic (0.61 MB). glslang and SPIRV-Cross, which compile custom
  shaders, are 3.5 MB; FreeType 0.6 MB, oniguruma (link matching) 0.5 MB, the image decoders
  0.25 MB, Dear ImGui (the terminal inspector) 0.25 MB, libpng and zlib 0.13 MB. Ghostty's build
  has no option to leave any of these out.
- **Sentry, 1.95 MB.**
- Nothing is generated data compiled as code: the biggest Swift `__const` is 0.06 MB.

### The script runtime

V8 through rusty_v8's prebuilt library (150.4.0, pointer compression), 41.4 MB stripped, by symbol:

| Part | MB |
| --- | --- |
| ICU data, embedded (`icudtl.dat`) | 10.8 |
| The optimizing compilers: Turboshaft and TurboFan 8.0, Maglev 3.2, Sparkplug 0.1 | 11.4 |
| Embedded builtins | 2.1 |
| WebAssembly | 1.7 |
| ICU code | 1.9 |
| The rest of V8: interpreter, parser, runtime, heap, API | 12.3 |
| Rust: the runtime itself, std, serde, and the Temporal and ICU4X crates V8 uses | 1.0 |

The runtime starts V8 with `--jitless`, so it never runs the compilers or WebAssembly; a V8 built
without them comes out 16.2 MB smaller, since not all of their code carries their namespace. The
ICU data is what `Intl` and localized formatting in scripts run on. "The script runtime: V8 or
JavaScriptCore" below weighs what to do.

## Plainly Settings allowance (2026-10-23)

The binary budget is 58.5 MB for the Plainly Settings page-map slice (PR #92). Its base,
`7e98b62a`, measured 57.9 MB in both Release and Nightly. The new map, grouped rows and
New Tasks page brought the binary to about 58.1 MB. The new presentation remains behind
a default-off switch, with the original Settings presentation still available. The slice
adds about 0.2 MB of compiled UI and copy.

This allowance covers the measured feature cost without removing settings or raising the
47 MB download and 118 MB installed budgets. Both remain below their limits at about
45.8 MB and 114.8 MB. Remove the legacy Settings presentation when Plainly is complete,
then remeasure before carrying its temporary duplication forward.

## What changed

| | Before | After |
| --- | --- | --- |
| `just install` (a plain Release build): installed | 152.8 MB | 116.9 MB |
| `just install`: app binary / host helper | 95.3 / 5.9 MB | 62.5 / 2.7 MB |
| `just install`: what it would cost to download | 47.5 MB | 43.4 MB |
| A release: installed / update archive / disk image | 116.4 / 43.3 / 43.9 MB | unchanged |

"Before" is the copy installed at 09:40 and "after" a build of the tree at 19:30, which has ten more
hours of features in it; stripping that same 09:40 binary takes it from 95.3 to 58.5 MB and its
host helper from 5.9 to 2.6 MB. Releases were already stripped, so their numbers don't move.

- **Local builds strip like releases.** Archives already stripped (`DEPLOYMENT_POSTPROCESSING` is on
  for the install action), but a plain Release build, which is what `just install` makes, didn't,
  so the app it installed carried 229,000 symbols and 40 MB that users never get.
  `Config/Release.xcconfig` (and so Nightly) now sets `DEPLOYMENT_POSTPROCESSING`,
  `STRIP_INSTALLED_PRODUCT` and `STRIP_STYLE = all` for every Release and Nightly build. The dSYM is
  still made from the unstripped binary first (same UUID, all 255,000 symbols), so Sentry
  symbolication is unchanged.
- **The budget is enforced** (above), so the next 10 MB shows up in the pull request that adds it.
- **Kotlin, C++ and Ruby are lexed** (`docs/decisions.md`, "Tree-sitter for highlighting"): their
  grammars are out of `Packages/CodeThemes`. On the same day's tree, the app binary went from 63.1 MB
  to 53.2 MB, the installed app from 117.4 to 107.5 MB and the update archive from 43.8 to 42.7 MB,
  and the budgets came down with them. All three still color keywords, types, strings, numbers and
  comments in transcript code blocks, light and dark; what they lose is what only a parse knows,
  like C++ template brackets versus comparisons, or Ruby symbols.
- **Updates come as deltas.** `release.sh` now seeds `generate_appcast`'s folder with the last few
  releases' archives (`docs/releasing.md`, "Delta updates"), so most updates are a delta of a few MB
  instead of the whole archive: between two release builds an hour (31 commits) apart it was 2.7 MB
  instead of 43.6 MB, and applying it reproduced the new app exactly. Users on an older build than
  the last three releases (two for Nightly) still download the whole archive.
- **The standalone host is stripped.** `host.sh` makes its dSYM first (15 MB, uploaded to Sentry
  with the app's, same UUIDs) and then strips it: the universal `native-host` that hosts download
  went from 10.6 MB to 4.6 MB, and still starts and serves.

## The script runtime: V8 or JavaScriptCore

The runtime is 35% of every download. `docs/script-runtime.md` chose V8 because JavaScriptCore's
public API has no heap limit and no way to stop a running script from another thread, and because
in-process JavaScriptCore would put untrusted code inside the app.

Measured 2026-10-19 on a heavily loaded Mac (load average 100 to 180), so CPU time, which load
inflates less than wall time, is what to compare. JavaScriptCore was measured with a 36 KB C harness
signed like the runtime (the App Sandbox with nothing granted, the hardened runtime, the script on
stdin, a `text()` binding); V8 is the runtime itself, over its protocol.

| | V8 today (rusty_v8's prebuilt) | V8, jitless build | JavaScriptCore |
| --- | --- | --- | --- |
| Runtime installed / in the download | 41.4 / 15.0 MB | 25.2 / 10.1 MB | the engine ships with macOS; a Swift runtime would be well under 1 MB |
| Start to result: wall / CPU (best of 15) | 16 / 7 ms | 16 / 7 ms | 17 / 8 ms |
| A CPU-bound script: 1.8 MB of JSON parsed 10 times, a 2-million sieve over a `Uint8Array`, string and regex work (CPU, best of 5) | 352 ms | 1,266 ms | 706 ms |
| Loops of calls / property writes / typed-array reads and writes (best of 3) | 135 / 178 / 251 ms | 34 / 68 / 1,835 ms | 74 / 101 / 331 ms |
| Peak memory, the CPU-bound script | 51 MB | 53 MB | 40 MB |
| Memory limit | exact: V8's near-heap-limit callback reports `memory` | the same | a footprint watchdog in the runtime (2 ms polling) stopped a runaway allocation at 149 MB for a 128 MiB limit |
| Stopping a script | the host's SIGKILL; `terminate_execution` when stdin closes | the same | the host's SIGKILL; the runtime exits when stdin closes (`JSContextGroupSetExecutionTimeLimit` exists too, as private API) |
| JIT | none (`--jitless`) | none, compiled out | none: the hardened runtime without the JIT entitlement leaves JavaScriptCore its interpreter |
| `Intl`, `toLocaleString`, `localeCompare` | yes, from 10.8 MB of embedded ICU data | yes | yes, from the system's ICU |
| Security fixes | when we bump the pinned crate | the same | with every macOS update |
| Build machines | Rust, a 37 MB V8 download, a 1 GB cargo cache | the same, if we publish the library; 45 minutes and 5 GiB to build it here | nothing |

What each V8 option is:

- **The jitless build** sets the arguments rusty_v8 already uses for iOS devices: `v8_jitless=true
  v8_enable_sparkplug=false v8_enable_maglev=false v8_enable_turbofan=false
  v8_enable_webassembly=false`, which leaves out 16 MB of compilers and WebAssembly the runtime never
  runs (it already starts V8 with `--jitless` and removes `WebAssembly`). Built from source with
  `build-v8-sandbox.py`'s pinned inputs and these arguments instead of the sandbox (45 minutes on
  this Mac under load; one unused-variable warning in V8's arm64 builtins stops it, so it also
  needs `treat_warnings_as_errors=false`, as rusty_v8's iOS build sets), the runtime passes all 17
  of its Rust tests and all 28 of `Packages/ScriptRuntime`'s, sandbox checks included. It is not
  the same speed, though: compiling the JIT out also drops the interpreter's feedback collection,
  so calls get faster and typed-array access much slower. Building with the tiers off but
  `v8_jitless=false` might keep today's speed; that's untested. It can only be the default as a
  library we publish once per V8 pin, checksummed in `build-script-runtime.sh` the way rusty_v8's
  own download is; `--sandbox`, which compiles V8 anyway, could take the same arguments.
- **Without ICU** (`v8_enable_i18n_support=false`) would take off 12 MB more (10.8 MB of data and
  ICU's code), but scripts would lose `Intl` and localized formatting, and rusty_v8's bindings call
  ICU directly, so the crate would need a patch. Not recommended.
- **Pointer compression** is already on. The startup snapshot is already embedded
  (`v8_use_external_startup_data=false`); moving it to a file would save nothing.

The decision's two objections to JavaScriptCore were about running it inside the app. Out of
process they mostly fall away: the host already enforces the time limit and cancellation with
SIGKILL, and a process can bound its own footprint. What JavaScriptCore still lacks is V8's exact
heap accounting and its optional memory sandbox (not in today's default build either). Its
interpreter is about as fast as V8's for what scripts do (calls, objects, JSON) and slower for
tight numeric loops. ES modules with top-level `await` are available through `JSScript` (macOS
10.15 and later).

**Decided 2026-10-19: V8 stays as it is**, neither moved to JavaScriptCore nor rebuilt without
its compilers. The recommendation was:

**Recommendation: move the runtime to JavaScriptCore.** It's the largest single cut available
(41 MB installed, 15 MB of every download, a third of it), it keeps `Intl`, takes Rust and V8 out of
every build, and gets its security fixes from macOS. The cost is rewriting the runtime's 1,200 lines
of Rust as a small Swift executable that speaks the same protocol (its 220-line bootstrap can stay),
so `Packages/ScriptRuntime` and its tests stay as they are and check the new runtime. A Linux host
would need another sandbox anyway (the App Sandbox is macOS-only) and could keep V8 there. If V8
stays, publish a library built without the compilers (with the memory sandbox in the same build)
and make it the default.

## Still to do

Largest first.

| What | Saves, installed / download | Owner |
| --- | --- | --- |
| libghostty without its embedded fonts (3.05 MB; the Nerd Font symbols render prompt icons) or custom shaders (glslang and SPIRV-Cross, 3.5 MB) | up to 6.5 / 2.5 MB | Terminal; needs a patch on the pinned Ghostty, since its build has no option |
| Lossy compression for the 24 alternate icons (lossless 1024 px images, 4.4 MB that zip can't shrink) | perhaps half of that, both | Icon artwork |
| Per-channel icon catalogs: needs the icon artist to export them that way. Xcode can't leave single imagesets out of a catalog per configuration, only whole catalogs, so the channel-only imagesets would move from `native/Assets.xcassets` into one catalog per channel that `Config/*.xcconfig` excludes elsewhere. Stable could drop `AppIcon-dev-*`, `AppIcon-halloween-dev-*`, `-nightly-*` and `-beta-*` (1.9 MB); `AppIcon-nightly-*` stays, since Nightly is an icon theme in every channel. Seasonal icons could come with their downloadable celebration pack instead | about 1.5 to 1.9 MB, both | Icon artwork, then the release pipeline |

Considered and not worth it now:

- **The script runtime on JavaScriptCore (41 / 15 MB) or V8 without its compilers (16.2 / 4.9 MB).**
  Brayden kept V8 as it is (above).
- **Sharing code between the app and its host helper.** ACP, NativeLink and the host protocol are in
  both (about 1.5 MB installed, 0.5 MB download). A shared framework would cost launch time and
  cross-module optimization on ACP's streaming path.
- **Dead code stripping** is already on in every configuration.
