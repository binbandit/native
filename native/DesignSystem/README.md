# DesignSystem

Native's tokens, components and patterns. Every color, font, size, radius and animation in the app
comes from here, so many contributors (people and agents, working in parallel) build screens that
look like one product: quiet neutral chrome, Geist type, outlined controls and color saved for
statuses, with Native's own brand and accents.

Open `DesignSystemGallery` (the "Gallery" preview, or `DesignSystemGallery.showWindow()` on the
Mac) to see everything in light and dark side by side.

## Rules

1. **Tokens only.** No literal colors, font sizes, spacing, radii or durations in feature views.
   If a value you need isn't here, add a token (or ask the design-system owner) instead of
   hard-coding it.
2. **Light and dark.** Every component has a preview showing both (`DSPreviewPair`); check both
   before calling a change done.
3. **Liquid Glass only for the control layer:** the floating composer
   (`ComposerSurface(isFloating: true)`) and toolbars. Never for content. Glass renders what's on
   it vibrantly, and on an active window's lighter glass an opaque gray takes the glass's own shade,
   so tokens drawn on glass resolve to translucent values there (`\.dsOnGlass`, set by
   `.dsGlassEffect(in:)`; `.dsBorder` and `.dsBorderHover` do). Check glass with the window active.
4. **The sidebar is translucent.** Nothing on it paints an opaque background: rows use the
   translucent `.dsHover`/`.dsSelected` fills, and a hand-built sidebar uses `.dsSidebarBackground()`
   (a split-view sidebar column, `.dsSidebarColumnTransparency()`, Settings' included). Chrome that
   continues the column, like the status bar, draws the column's own look (`StatusBarSurface` does)
   rather than a material of its own, so the two read as one band at every level, in both window
   states. Anything see-through follows
   `\.dsTransparency`: overlays use `.dsOverlayBackground(in:)` or `.dsPopoverBackground()`, floating
   controls `.dsGlassEffect(in:)` or `.dsGlassButtonStyle()`, never a material or glass directly.
   Code is set with `.codeTextStyle(_:)` and colored with `HighlightedCode`, never `.dsMono` alone.
5. **One pattern per situation.** Use the patterns below; don't invent a new error box, empty state,
   loader or time format. Agree on a new one here first. An animation that runs as long as
   something works or shows goes through `LayerMaskedView` (Core Animation), never a SwiftUI
   animation or `TimelineView(.animation)`, which re-render the whole window every frame.
6. **Mac and iPad.** Code here compiles for macOS and iPadOS (`scripts/check-ios.sh
   native/DesignSystem`). Use the adapters in `Tokens/Platform.swift` (`DSPlatformFont`,
   `DSPasteboard`, `.dsFocusShape`, `.dsHitTarget`, `DS.isTouchPlatform`) rather than AppKit. Touch
   targets reach 44pt without changing the visuals, and nothing is reachable only by hovering.
7. **Built like a module.** The folder becomes its own SwiftPM target: public API is `public`, the
   rest is internal or private, and nothing here imports app models, ACP or features. Adapters to
   app types live with the app (e.g. `Views/Transcript/FileDiff+DiffView.swift`).
8. **Accessible and native.** Every control has an accessibility label, tooltips use `.help`,
   hover uses `.trackHover`, animations respect Reduce Motion, and keyboard shortcuts show in
   tooltips.
9. One family per file, files under about 400 lines, previews and gallery sections built from
   fixtures (`Gallery/GalleryFixtures.swift`), never from app models.

## Conventions

- Colors are `Color` statics with a `ds` prefix on `ShapeStyle`, so leading-dot works:
  `.foregroundStyle(.dsTextSecondary)`, `.fill(.dsHover)`, `Color.dsAccent`.
- Fonts likewise: `.font(.dsBody)`, `.font(.dsCalloutSemibold)`, `.font(.ds(15, weight: .medium))`
  for a one-off. Text views outside SwiftUI use `DSTypography.platformFont(size:weight:design:)`.
- Animations: `.dsQuick`, `.dsStandard`, `.dsPanel`, `.dsDisclosure`, `.dsPopover`.
- Metrics live in `DS`: `DS.Space` (2-32), `DS.Radius` (small 2, control 4, row 6, card 8, panel 12),
  `DS.Size`, `DS.Composer`, `DS.Window`, `DS.Shadow`, `DS.Tracking`.
- The accent follows the app-icon theme: `.dsAccentPalette(themeID:)` on each window's root.
  `original` is graphite / off-white; color is for statuses. "Needs you" states use `.dsAttention`.

## Tokens

| File | What |
| --- | --- |
| `Tokens/TokensColor.swift` | Layers, translucent fills, borders, text, semantic and chart colors. Dark is the Instrument palette: content #0D0D0E, sidebar, chrome and code wells #070708, hairlines #1F1F22, control outlines #2E2E32, text #E9E9E6 / #A5A5A8 / #85858A |
| `Tokens/AccentPalette.swift` | `DSAccentPalette` per icon theme (original, cobalt, fern, ember, prism, arcade, glass, nightly), contrast-checked |
| `Tokens/TokensTypography.swift` | Geist and Geist Mono (bundled, SIL OFL, `Fonts/OFL.txt`), UI text at 12pt, sidebar and composer at 13pt, one display line at 40pt (`dsDisplay`, lined up with `DSTypography.displayIndent`) |
| `Tokens/TokensLayout.swift` | Spacing, radii, sizes (including `contentColumn` 760, `listRow` 26), shadows |
| `Tokens/TokensMotion.swift` | Animations and `.trackHover` (instant in, 100ms out) |
| `Tokens/Platform.swift` | macOS/iPadOS adapters and touch metrics |
| `Tokens/TokensTransparency.swift` | `DSTransparency` (Solid, Subtle, Standard) from `.dsTransparency(_:)`; Reduce Transparency forces Solid |
| `Tokens/TokensLightTone.swift` | `DSLightTone` (Paper, Wool) from `.dsLightTone(_:)`; neutrals, text and statuses have Wool values |
| `Tokens/TokensDarkTone.swift` | `DSDarkTone` (Standard, True Black) from `.dsDarkTone(_:)`; True Black puts content, sidebar and chrome on #000 and lifts lines, selection and raised surfaces |
| `Tokens/TokensCode.swift`, `TokensCodeFont.swift` | Code themes (`.dsCodeThemes`), `HighlightedCode`, `.dsCodeBlockBackground`, and the code font (`.codeTextStyle(_:)`) |

## Components

| Component | What it is |
| --- | --- |
| `SidebarNavItem`, `SidebarRowMenu` | The sidebar's navigation rows: icon, label, a shortcut hint on hover, an optional trailing menu |
| `.buttonStyle(.header(isOn:iconOnly:))` (`HeaderButtonStyle`) | The window header's outlined controls: 24pt, surface fill, 1pt border, 4pt radius, selected while what they toggle is open; the same chrome as Open In |
| `SidebarCollapseButton`, `HistoryNavigationButtons`, `WindowToolbarButton` | The sidebar toggle right after the window controls, and back and forward arrows, as ghost glyphs (color-only hover, safe in a macOS toolbar) |
| `UpdateButton` | The accent update tag right of the sidebar toggle |
| `UsageMeter` | A usage bar (accent, warning at 80%, error at 100%) |
| `ActivityHeatmap` | GitHub's contribution graph: 53 weeks of days, month and weekday labels, five accent steps over a neutral empty square; hover, tap or arrow keys pick a day, and every square tells VoiceOver its exact count |
| `ProjectGroup`, `ProjectRow`, `ProjectAvatar` | Collapsible project groups: avatar, name, task count while collapsed |
| `TaskRow` (+ `leading`/`accessory` slots), `TaskBadge`, `DiffStatLabel`, `CompactAgeText` | Task rows: one leading visual, then a trailing badge, the accessory and the diff or age; on hover Archive takes the age's place, so controls in the accessory stay reachable |
| `TaskStatus`, `StatusIndicator`, `DotGridLoader` | Agent states and the animated dot-grid loaders |
| `ContextUsageRing` | A small ring for how much of the context window a session has used |
| `ComposerSurface`, `ComposerControlsBar`, `.pill` / `.pillChrome`, `PillIcon`, `PillMenu`, `EffortBars`, `ComposerSendButton`, `ComposerStopButton`, `ComposerChip` | The composer: outlined sections with 1pt rules, 28pt pills |
| `SearchField` | The one search and filter field: a magnifier, a clear button once something's typed, Escape to clear, an optional trailing accessory (a shortcut hint, a record-keys button), no fill of its own |
| `.ds(_:size:iconOnly:)` buttons, `IconButton`, `Badge`, `Kbd`, `Card`, `SeparatorLine`, `SectionHeader`, `StatusDot` | Buttons, shortcut caps, badges and cards |
| `DiffView`, `DiffStats`, `DiffStatsText` | Line diffs with a colored bar, line numbers and tinted lines; shared by the transcript and Git |
| `StatusBarSurface`, `.statusBarSegment(_:isActive:)`, `.statusBarCompactForm { }`, `StatusBarGlyph`, `StatusBarDivider`, `StatusBarSeparator` | The window's bottom strip: the sidebar column's look under a hairline, `DS.Size.chromeBar` tall, tertiary caption text, footer-sized glyphs, hairlines between items, color-only hover. Narrow windows shorten before they drop: items with a compact form (the same glyphs, fewer words) take it, innermost first, and only then do whole items drop. Nothing is cut mid-word |
| `IconThemePicker`, `IconThemeOption` | The settings select showing the current app icon; a popover lists each option's thumbnail, name, badge and note, with a checkmark. Options are data, so plugins can add their own |
| `PopoverPanel`, `PopoverPanelFootnote`, `.dsPopover(isPresented:)` | A popover that explains something: glyph and title header, hairline, content, on the overlay backdrop |
| `.dsHoverCard(_:)`, `DSHoverCardState` | A popover that opens when the pointer rests on its anchor (500ms, or 100ms while another shows), stays while the pointer is on the anchor or the card, and closes 200ms after it leaves both; one at a time. On touch the anchor's tap toggles it |
| `CappedHeightScrollView` | Natural height up to a cap, then scrolls |
| `NativeMark`, `NativeLockup`, `.nightSky(isEnabled:)`, `NightlyMark` | Native's brand: the interlock emblem from the app icon, the wordmark, and the nightly sky and moon |
| `LaunchAnimationView`, `.launchScreen(isPresented:)` | The emblem tracing in and interlocking while agents start |

## Patterns: use these, don't invent new ones

| Situation | Use |
| --- | --- |
| A failure | `ErrorState(what, recovery: what Native did, suggestion: what you can do, details:, primary:)`, `.inline` or `.pane` |
| Any other inline notice (offline, sign-in expired) | `NoticeBanner(tone:title:detail:) { one action }` |
| Nothing to show | `EmptyStateView(what, systemImage:, message: why, actionTitle:, action:)` |
| Something that can be taken back | `.undoToast($item)` with `UndoToastItem(message) { undo }`, instead of a confirmation, on the content above any status bar. A pane whose content scrolls carries `.undoToastAnchor()` outside its scroll view, so toasts raised inside show where the user is looking. An Undo anywhere else (a notice, a composer toast) is `.ds(.secondary)` on the message's first baseline, with the message in the label's size; in Settings, `.buttonStyle(.settings)` |
| Usage limits | `LimitStatus` (one value from Usage), rendered by `LimitBanner` and `LimitChip`, worded by `LimitStatus.line(now:)` |
| Task state | `TaskStatus` + `StatusIndicator`; paused and limited included |
| Loading | `DotGridLoader`, or `LoadingStateView(what)` filling a pane; never ad-hoc spinners |
| Something blocked on the user, in chrome | `.statusBarSegment(.attention)`: the only boxed item in the status bar, one at a time |
| Details on click | `.dsPopover` with a `PopoverPanel` |
| Details on hover (a task's pull request) | `.dsHoverCard` with a `PopoverPanel` at `DS.Size.hoverCardWidth`; the anchor's click still does its own thing, and everything in the card is also in a context menu or a command |
| An icon-only button | `Button("Title", systemImage:)` with `.ds(_, iconOnly: true)` or `.pill(isSquare: true)`, or `IconButton`: the title stays VoiceOver's label. Never a bare `Image` label |
| Elapsed time | `ElapsedTimeText(since:until:)`: ticks while running, a total once done. Anything else that counts seconds reads `DSSecondClock.shared.now` and holds it from `.task { await DSSecondClock.shared.hold() }`: one 1 Hz clock for the app, never a `TimelineView` per label |
| Ages ("5m", "3h") | `CompactAgeText(date:)`. Other ages and countdowns use `DSMinuteTimeline { now in ... }` around just the time-dependent content, or read `DSMinuteClock.shared.now` in their own small view: one clock that ticks each minute while the app can be seen and stops while it's hidden, never a `TimelineView(.everyMinute)` per row |
| A tool call's kind | `DSToolGlyph` (read, search, edit, command, web, MCP, think, subagent): one glyph per kind wherever tool work shows |
| Searching or filtering a list | `SearchField`, never a hand-built `TextField` with a magnifier |
| Counts, sizes, times | `DSFormat`: `compactAge`, `time`, `countdown`, `timeAndCountdown`, `duration`, `thoughtFor`, `tokens`, `percent`, `share`, `lineCount`, `diffStat`, `cost`, `memory`, `cpu` |

## Do and don't

- Do give the window header's controls one look: a control that acts on the session (Open In, Show
  Changes, the terminal) is an outlined `.buttonStyle(.header(isOn:iconOnly:))`, in a `ToolbarItem`
  with `.sharedBackgroundVisibility(.hidden)`. Window chrome (the sidebar toggle, back and forward)
  stays a ghost `WindowToolbarButton`. Leave the system's toolbar glass to system controls, and put
  status that belongs to the conversation (MCP servers, context) in the composer instead.
- Do put a hand-built toolbar control in a `ToolbarItem` with `.sharedBackgroundVisibility(.hidden)`;
  don't add your own fill on top of a system control.
- Do give rows `SidebarRowButtonStyle` (pressed wash) and let the row own hover and selection.
- Do use `.dsAttention` and `Badge(tone: .attention)` for anything waiting on the user; keep the
  accent for the user's own actions (send, update, primary buttons).
- Don't use system colors (`.secondary`, `.green`) in feature views; use the `ds` tokens.
- Don't vendor other products' artwork. Brand pieces here are Native's own.

## Verify

```sh
xcodebuild -project native.xcodeproj -scheme native -derivedDataPath /tmp/native-dd/<you> build
scripts/check-ios.sh native/DesignSystem
```

Then look at the gallery in both appearances, and at your screen in the running app.

### Playful working spinners

Settings > Appearance > Playful spinners defaults to off. Each task model keeps one saved random
choice from sweep, ripple, orbit, rain, checkerboard, snake and breathe. Its sidebar, transcript and
Tasks panel share that choice through `dsWorkingAnimation`; other loading states keep their existing patterns.
All variants use the same neutral 3x3 grid and 2.4-second Core Animation loop. Reduce Motion shows
the still grid. The Gallery and Appearance show every variation.
