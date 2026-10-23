# Terminal

Every task has a terminal panel under its composer: tabs of real shells that start in the task's
folder (its worktree, when it has one), drawn by libghostty, the library inside
[Ghostty](https://ghostty.org). ⌃` shows and hides it, ⌃⇧` adds a tab (`docs/keyboard.md`), and
the task's toolbar has a terminal button for pointer and touch.
The button keeps the number of open tabs visible when the panel is hidden or reduced in height.
It uses the shared working signal while a foreground command or project-action job runs, and a
red failed signal with "Failed" when a command fails or a terminal cannot start. All tabs count:
running work and a failure in separate tabs both remain visible. Clicking shows the terminal;
the existing keyboard shortcuts are unchanged.
Why libghostty, and the pin, are in `docs/decisions.md`.

## How it fits together

```
 native/Terminal (app)                                   Packages/Terminal (UI-free, tested)
 ┌──────────────────────────────────────────────┐        ┌───────────────────────────────────┐
 │ TerminalCommands   ⌃`  ⌃⇧`  (View menu)       │        │ TerminalTabList   tabs, names,    │
 │ .terminalPanel(for:)  → TerminalPanel         │        │                   selection       │
 │   tab bar · resize divider · states           │        │ TerminalStatus    running/exited/ │
 │ TerminalStore ── TerminalPanelModel per task  │ uses   │                   failed to start │
 │   └ TerminalEngine (protocol) ─ TerminalSurface├──────▶│ TerminalTheme/Colors/Style        │
 │       └ GhosttyRuntime ─ GhosttySurfaceView   │        │ GhosttyConfiguration  settings →  │
 │            (Engine/, macOS + libghostty only) │        │                   Ghostty config  │
 └──────────────────────────────────────────────┘        └───────────────────────────────────┘
```

- **Panels outlive views.** `TerminalStore` keeps a `TerminalPanelModel` per task (keyed by
  `SessionKey`), and each tab owns its terminal view, so shells and scrollback survive hiding the
  panel, switching tabs and selecting other tasks. A tab's shell ends when its tab closes, or when
  `TerminalStore.closeTerminals(for:)` runs for a task that went away.
- **The model never sees AppKit.** Tabs talk to a `TerminalSurface` and the store to a
  `TerminalEngine`; on the Mac those are `GhosttySurfaceView` and `GhosttyRuntime`
  (`native/Terminal/Engine`). A host-backed engine slots in behind the same protocols (below).
- **Native's settings, or the user's Ghostty config.** By default `GhosttyConfiguration` renders
  Native's settings and colors as a Ghostty config, and the user's own config is never read.
  Colors come from the design system (`TerminalChrome.designSystem`): the sunken surface code blocks
  use, primary text, an accent cursor and selection, and ANSI colors from `TerminalStore.appTheme`
  (`TerminalTheme.native` until the code-theme setting sets one), light and dark. Appearance,
  accent and transparency changes restyle running terminals live. "Use my Ghostty settings" loads
  the user's config instead (below).
- **`TERM` is `xterm-256color`.** Ghostty's own `xterm-ghostty` terminfo is bundled (and its
  shell integration found through it), but setuid programs such as `top` and anything under
  `sudo` ignore `TERMINFO`, and remote machines don't have it, which is Ghostty's most common
  support question. Programs still get truecolor (`COLORTERM`) and Ghostty's extensions by
  querying the terminal. A Ghostty config that sets `term` wins.
- **The shell** is the user's login shell from the user database (`getpwuid`, what
  `dscl . -read ~ UserShell` shows), not `$SHELL`, which an app opened from the Dock may not have.
  libghostty runs it the way Terminal and Ghostty do (`login -flp user /bin/bash -c 'exec -l
  <shell>'`), so it's a login shell and profile files load. Settings ▸ Terminal ▸ Shell picks
  another (`/etc/shells`, or any program). A missing shell gets "<path> isn't there" with
  "Use /bin/zsh"; one that quits on launch gets Try Again and "Use /bin/zsh". With "Use my Ghostty
  settings" on, the config's `command` wins. The shell is resolved where the terminal runs: a
  host-backed engine resolves the host's login shell, never the client's (`TerminalLoginShell`).
- **Transparency** follows the app's setting (`\.dsTransparency`): Solid, Subtle and Standard
  set libghostty's `background-opacity` to 1, 0.92 and 0.85, over a behind-window blur the panel
  draws (libghostty's own `background-blur` blurs the whole window through private API, so Native
  doesn't use it). Only the default background is translucent; text and colored cells stay opaque.
  Reduce Transparency forces 1, even over a Ghostty config's `background-opacity`.
- **Tabs** are named by their shell's title (the folder, or the running command), numbered when two
  show the same title, and fall back to "Terminal", "Terminal 2", ... once their shell exits.
- **Activity** lives in `TerminalTabList`, summarized across tabs by `TerminalActivitySummary`.
  The engine reports busy-state changes independently of the panel's visibility, and keeps the
  last command's exit code until the next command starts, the shell restarts or the tab closes.
  An idle shell stays open without a working signal. Shell commands use libghostty's shell
  integration to distinguish the prompt from foreground work and report exit codes; shells with
  integration disabled cannot reliably distinguish idle from busy or report command failures.
  Background jobs that have returned control to the prompt are outside this signal.
- **Jobs.** A tab can run a command instead of a shell (`TerminalStore.run(_:for:)`, used by
  project actions, `docs/actions.md`): it's named after the job, shows a loader, then a green, red
  or gray dot, the elapsed time and Stop while it runs (⌃C, then End Now), and a banner with how it
  ended (exit code and duration) and Run Again. Running the same job again reuses its tab. The
  command reports its exit status with OSC 133 (`133;D;<status>`), since `login(1)` hides it.
- **Keys.** Native's menu shortcuts come first while a terminal has focus, then the terminal's key
  bindings, then the shell. In Native's settings Ghostty's default bindings are cleared (they claim
  ⌘N, ⌘W, ⌘Q, ⌘T) and only the terminal-local ones in `docs/keyboard.md` come back. Copy, paste and
  select all go through the Edit menu. Input runs through AppKit's input method system first, so
  dead keys, CJK input and dictation work.
- **Settings ▸ Terminal** (`SettingsPane.terminal`): use my Ghostty settings, import from Ghostty,
  shell, font family (any installed monospaced font; Geist Mono by default), size, cursor,
  scrollback in lines (10,000 by default), and colors (Native's, or imported).

### Using your Ghostty settings

With "Use my Ghostty settings" on, terminals load the user's own config through libghostty's
config loader, so theme, palette, font family and size, font features, cursor, padding,
background opacity and key bindings come out exactly as in Ghostty. Native only reads these files;
it never writes the config, its themes or Ghostty.app.

- **Files**, in Ghostty's order (later wins): `$XDG_CONFIG_HOME/ghostty/config` (default
  `~/.config/ghostty`), then `config.ghostty` there, then the same two in
  `~/Library/Application Support/com.mitchellh.ghostty`, then every `config-file` they include.
  Native loads them one by one rather than through `ghostty_config_load_default_files`, which
  writes a template config when none exists. Ghostty.app doesn't need to be installed.
- **Themes** resolve by name in `~/.config/ghostty/themes`, then Ghostty.app's bundled themes
  (`Contents/Resources/ghostty/themes`, found wherever the app is installed). Native doesn't ship
  themes: at launch it joins its own terminfo and shell integration with Ghostty.app's themes in
  a resources folder in its caches (`ghostty-resources`, symlinks) and points libghostty there.
  Without Ghostty.app, only the user's themes are found, and the settings page says so. A theme
  that isn't found is a config problem like any other (below).
- **What Native overrides**, after the user's config (`GhosttyConfiguration.userConfigOverrides`):
  `wait-after-command = true` (Native shows the exited state and keeps the tab),
  `confirm-close-surface = true` (enables the busy-state query; Native owns the close prompt),
  `quit-after-last-window-closed = false`, `clipboard-read = deny` (Native has no prompt for
  programs reading the clipboard; they can still copy), and `background-opacity = 1` when Reduce
  Transparency is on. Before the user's config it sets `term = xterm-256color`, which the config
  can change.
- **What does nothing embedded**: window and app settings Native owns, such as `window-decoration`,
  `macos-titlebar-*`, `window-width`/`-height`/`-position`, `fullscreen`, `maximize`,
  `window-save-state`, `background-blur` (see Transparency), `quick-terminal-*`, `initial-window`,
  `auto-update`, `desktop-notifications`, `confirm-close-surface` and `working-directory` (each tab
  starts in its task's folder).
- **Key bindings** from the config work, after Native's menu shortcuts. `new_tab`, `next_tab`,
  `previous_tab`, `goto_tab`, `last_tab`, `close_surface` / `close_tab` and `reload_config` act on
  Native's terminal tabs; bindings for windows, splits, fullscreen, the quick terminal, the
  inspector, the command palette and search do nothing.
- **Problems**: libghostty's diagnostics, each with its file and line, show in Settings and above
  the terminal ("Your Ghostty config didn't load, so Native's terminal settings are in use"), and
  terminals use Native's settings until the config loads cleanly.
- **Changes** apply as they're saved: Native watches the config files, their folders, includes and
  `~/.config/ghostty/themes`, and reloads (a Reload button covers anything else).
- **Code theme**: the Ghostty config's colors win; Native's code theme doesn't apply to the
  terminal while this is on.

"Import from Ghostty" is the snapshot instead of the live link: it reads the same files (with a
small parser in `Packages/Terminal`, `GhosttyImporter`) and copies the font family and size, the
theme or palette (resolved for light and dark, with the config's own colors over the theme's), the
cursor and the scrollback limit into Native's settings, after showing each change. Undo restores
the previous settings.

### States

| Situation | What the user sees |
| --- | --- |
| Build without libghostty | "Terminal isn't available in this build", how to enable it, and Copy Command |
| libghostty didn't start | The error, and to reopen Native |
| The shell exits | Its last output stays, with "The shell exited · press any key to close · Restart Shell"; the tab gets a gray dot |
| The shell isn't there | "<path> isn't there", Use /bin/zsh and Choose Shell…; red dot |
| The shell quits on launch (broken profile, bad command) | Its output stays, with "The shell didn't start", Try Again and Use /bin/zsh; red dot |
| "Use my Ghostty settings" with no config | Settings explains where Native looked; Native's settings apply |
| The Ghostty config has errors | Each problem with its file and line, in Settings and above the terminal; Native's settings apply |
| The task's folder is gone | "This task's folder is gone", Open in Home Folder and Close Tab |
| Closing a tab with a program running | A confirmation, since it can't be undone |
| Pasting text that would run commands | A confirmation (Ghostty's paste protection) |

To try the failure states by hand: `open -n Native.app --args -NativeTerminalCommand /nonexistent`
runs that command instead of the login shell. Pressing any key in an exited tab closes it, and
focus moves to the next tab.

## Building libghostty

```sh
scripts/build-libghostty.sh          # fetch the pinned Zig and Ghostty, then build (once)
scripts/build-libghostty.sh --clean  # remove all of it
```

Everything lives in `~/Library/Caches/native-build` (about 2 GB, mostly Zig's cache):
`zig/0.16.0`, `ghostty/src` at the pinned commit, and `libghostty/`, which is what Xcode uses:
`include/GhosttyKit/{ghostty.h,module.modulemap}`, `lib/libghostty.a` (static, arm64, ReleaseFast,
about 130 MB before dead-stripping; about 18 MB linked), and `share/` (terminfo, shell
integration, Ghostty's license).

The **Build libghostty** phase runs first in the app target (`--xcode`), and only when its inputs
changed: the script (which holds the pin), `libghostty/VERSION` (rewritten by every staged build,
from any checkout or by hand), or the bundle's copies of the resources. It never touches the
network: when the staged build matches the pin it only syncs the resources into the bundle
(about 30 ms); when the pin changed and the toolchain and source are present, it rebuilds; when
they're missing it warns ("Terminal isn't available in this build: ...") and exits 0. The app finds
the module through `SWIFT_INCLUDE_PATHS` and `canImport(GhosttyKit)`, and the module map links
libghostty and its frameworks, so a build without it compiles and links cleanly.

Timings on an M-series Mac: the first `scripts/build-libghostty.sh` took 7.5 minutes (fetching Zig
packages and compiling); a rebuild after a pin change is a few minutes; a no-op run is 30 ms.

### Changing the pin

1. Update `GHOSTTY_COMMIT` and, if Ghostty's `build.zig.zon` asks for a different
   `minimum_zig_version`, `ZIG_VERSION` and both SHA-256s (from ziglang.org's `index.json`) in
   `scripts/build-libghostty.sh`. Bump the `flags=` stamp if you change build flags.
2. Run it, build Native, and fix what changed in `ghostty.h`. Read Ghostty's own
   `macos/Sources/Ghostty/Surface View/SurfaceView_AppKit.swift` and `Ghostty.App.swift` at the new
   commit: the engine follows them closely.
3. Update the decision record.

## Research: embedding Ghostty (October 2026)

**libghostty (`ghostty.h`, GhosttyKit).** The C API Ghostty's macOS app is built on, compiled from
Zig into a static library and wrapped as `GhosttyKit.xcframework` (`zig build
-Demit-xcframework=true -Dxcframework-target=native`). The shape:

- `ghostty_init` once; a config (`ghostty_config_new`, `_load_file`, `_finalize`; settings only
  arrive as config files or CLI arguments); one app (`ghostty_app_new`) with runtime callbacks:
  `wakeup` (call `ghostty_app_tick` on the main thread), `action` (a tagged union of about 70
  actions: titles, working directory, child exited, open URL, mouse shape, cell size, and the
  tab/split/window requests an embedder can ignore), clipboard read/confirm/write, and close
  surface.
- One surface per terminal (`ghostty_surface_new`) given an `NSView` or `UIView`, scale, working
  directory, optional command and environment. libghostty makes the view layer-hosting with an
  `IOSurfaceLayer` and renders into it with Metal on its own thread; a termio thread runs the
  child on a pty. The embedder forwards size (pixels), content scale, focus, occlusion, display ID,
  keys (with text from AppKit's input methods), preedit, mouse and scroll, and runs binding actions
  (`copy_to_clipboard`, `paste_from_clipboard`, ...).
- **Stability.** The header says it "isn't meant to be a general purpose embedding API (yet)" and is
  documented only in Zig. It changes without notice: between 1.3.1 and the pinned commit the
  clipboard callbacks gained MIME-typed contents, a read result and an explicit deny. It's
  exercised daily by Ghostty's own app, so it works; it just has to be pinned and ported on
  purpose.

**libghostty-vt (`ghostty/vt.h`, `-Demit-lib-vt`).** The standalone, dependency-free library being
extracted from Ghostty. In 1.3.1 it was parsers only (OSC, SGR, key encoding, paste). At the pinned
commit it's a full terminal: `ghostty_terminal_new` / `_vt_write` / `_resize` / `_scroll_viewport`,
an incremental **render state** with dirty tracking for custom renderers, **snapshots** that
encode a terminal and restore it incrementally, a formatter (plain text, VT, HTML), search,
selection, kitty graphics, and key, mouse and focus encoders. It has no renderer: the embedder
draws cells. Its header says it's work in progress with breaking changes expected.

**Platforms.** At the pinned commit the full libghostty builds for macOS only; Ghostty's build
refuses iOS for it ("only libghostty-vt supports iOS"). libghostty-vt builds for iOS (13+), macOS,
Linux and WebAssembly.

**License.** Ghostty is MIT (© Mitchell Hashimoto, Ghostty contributors). The static library also
contains its permissively licensed dependencies (Oniguruma, libpng, zlib, simdutf, Highway,
Dear ImGui for the inspector, FreeType). Native ships Ghostty's `LICENSE` in the bundle
(`Contents/Resources/ghostty/LICENSE`); a credits screen should list the rest before release.

**Toolchain.** Ghostty pins a Zig minor version (`minimum_zig_version`, checked by its build):
1.3.1 needs 0.15.x, the pinned tip 0.16.0. Homebrew's Zig is 0.17. Zig 0.15.2 can't link anything
targeting macOS 27 (undefined libSystem symbols for the native target; targeting
`aarch64-macos.26.0` works, but Zig's build runner always targets the host), which is why Native
pins a tip commit rather than the release.

## Remote and iPad

Native's rule is that only hosts touch the machine (`docs/architecture.md`, "Clients and hosts").
Phase 1 runs shells on the Mac running the app, which is its own host. What a host-backed terminal
needs:

- **libghostty's surface can't render a stream today.** Its termio has one backend, `exec`: the
  surface always forks the child on a pty it opens itself (unchanged at Ghostty tip, October 2026).
  There's no manual or external IO mode for feeding output bytes in and taking input bytes out.
- **Mac client, remote host: works now, with a relay.** A surface's `command` can be a small
  relay process (`native-pty-relay <host> <terminal id>`) that connects to the host and copies
  bytes and window size both ways, the way `ssh -t` does. The host owns the real pty and shell; the
  local pty only carries bytes. libghostty rendering, input and selection stay exactly as they are.
  What's missing is the host side: a terminal channel in the host protocol (open with cwd and
  size, write, resize, close, exit status) and the relay.
- **iPad: libghostty-vt plus Native's own renderer.** iPadOS can't spawn processes, and the full
  libghostty no longer builds for iOS. The client keeps a `GhosttyTerminal` per tab, feeds it the
  host's output (`ghostty_terminal_vt_write`), encodes keys, mouse and focus with libghostty-vt's
  encoders and sends them to the host, and draws the render state's dirty rows itself (Metal or
  Core Text). Attaching mid-session uses snapshots: the host runs libghostty-vt too, so it can
  encode the current screen and scrollback for a client that connects, then stream bytes after
  it. That also gives Mac clients reattach-after-quit for free.
- **What upstream could add.** A manual termio backend for surfaces (bytes in, a write callback
  out, a resize callback) would let the Mac use the full renderer without a relay, and an iOS build
  of the full library would give the iPad the same renderer. Until then the split above needs no
  Ghostty changes.

The seams are in place: `TerminalEngine` / `TerminalSurface` are what a host engine implements;
`TerminalLaunch` is what it starts with; the package's model and theming are platform-neutral.
