# DesignSystem

Native's tokens, components and patterns. Every color, font, size, radius and animation in the app
comes from here, so many contributors (people and agents, working in parallel) build screens that
look like one product. The look follows Factory (sidebar top half, composer, buttons, type) and
Conductor (projects and tasks, statuses, loaders), with Native's own brand and accents.

Open `DesignSystemGallery` (the "Gallery" preview, or `DesignSystemGallery.showWindow()` on the
Mac) to see everything in light and dark side by side.

## Rules

1. **Tokens only.** No literal colors, font sizes, spacing, radii or durations in feature views.
   If a value you need isn't here, add a token (or ask the design-system owner) instead of
   hard-coding it.
2. **Light and dark.** Every component has a preview showing both (`DSPreviewPair`); check both
   before calling a change done.
3. **Liquid Glass only for the control layer:** the floating composer
   (`ComposerSurface(isFloating: true)`) and toolbars. Never for content.
4. **The sidebar is translucent.** Nothing on it paints an opaque background: rows use the
   translucent `.dsHover`/`.dsSelected` fills, and a hand-built sidebar uses `.dsSidebarBackground()`
   (a split-view sidebar column, `.dsSidebarColumnTransparency()`). Anything see-through follows
   `\.dsTransparency`: overlays use `.dsOverlayBackground(in:)` or `.dsPopoverBackground()`, floating
   controls `.dsGlassEffect(in:)` or `.dsGlassButtonStyle()`, never a material or glass directly.
   Code is set with `.codeTextStyle(_:)` and colored with `HighlightedCode`, never `.dsMono` alone.
5. **One pattern per situation.** Use the patterns below; don't invent a new error box, empty state,
   loader or time format. Agree on a new one here first.
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
| `Tokens/TokensColor.swift` | Layers, translucent fills, borders, text, semantic and chart colors. Neutrals are Factory's "Factory" preset (dark content #171717, composer outline #3e3e3e); statuses are Conductor's |
| `Tokens/AccentPalette.swift` | `DSAccentPalette` per icon theme (original, cobalt, fern, ember, prism, arcade, glass, nightly), contrast-checked |
| `Tokens/TokensTypography.swift` | Geist and Geist Mono (bundled, SIL OFL, `Fonts/OFL.txt`), Factory's scale (UI text 12pt, sidebar and composer 13pt) |
| `Tokens/TokensLayout.swift` | Spacing, radii, sizes (including `contentColumn` 760, `listRow` 26), shadows |
| `Tokens/TokensMotion.swift` | Animations and `.trackHover` (instant in, 100ms out, as Factory) |
| `Tokens/Platform.swift` | macOS/iPadOS adapters and touch metrics |
| `Tokens/TokensTransparency.swift` | `DSTransparency` (Solid, Subtle, Standard) from `.dsTransparency(_:)`; Reduce Transparency forces Solid |
| `Tokens/TokensLightTone.swift` | `DSLightTone` (Paper, Wool) from `.dsLightTone(_:)`; neutrals, text and statuses have Wool values |
| `Tokens/TokensCode.swift`, `TokensCodeFont.swift` | Code themes (`.dsCodeThemes`), `HighlightedCode`, `.dsCodeBlockBackground`, and the code font (`.codeTextStyle(_:)`) |

## Components

| Component | Mirrors |
| --- | --- |
| `SidebarNavItem`, `SidebarRowMenu` | Factory's sidebar navigation rows |
| `SidebarCollapseButton`, `HistoryNavigationButtons`, `WindowToolbarButton` | Factory's toggle placement; Conductor's ghost glyphs and arrows (color-only hover, safe in a macOS toolbar) |
| `UpdateButton` | Factory's accent update tag right of the sidebar toggle |
| `UsageMeter` | Factory's usage bar (accent, warning at 80%, error at 100%) |
| `ProjectGroup`, `ProjectRow`, `ProjectAvatar` | Conductor's repository groups |
| `TaskRow` (+ `leading`/`accessory` slots), `TaskBadge`, `DiffStatLabel`, `CompactAgeText` | Conductor's workspace rows: one leading visual, trailing badge, diff or age |
| `TaskStatus`, `StatusIndicator`, `DotGridLoader` | Conductor's statuses and Lottie dot-grid loaders (ported keyframes) |
| `ContextUsageRing` | Conductor's context ring |
| `ComposerSurface`, `ComposerControlsBar`, `.pill` / `.pillChrome`, `PillMenu`, `EffortBars`, `ComposerSendButton`, `ComposerStopButton`, `ComposerChip` | Factory's composer, measured at 1x |
| `.ds(_:size:)` buttons, `IconButton`, `Badge`, `Kbd`, `Card`, `SeparatorLine`, `SectionHeader`, `StatusDot` | Factory core-ui v2 buttons and Kbd; Conductor badges and cards |
| `DiffView`, `DiffStats`, `DiffStatsText` | Factory's diff layout; shared by the transcript and Git |
| `StatusBarSurface`, `.statusBarSegment(_:isActive:)`, `StatusBarGlyph`, `StatusBarDivider`, `StatusBarSeparator` | Orca's status bar in Factory's chrome: the sidebar backdrop under a hairline, `DS.Size.chromeBar` tall, tertiary caption text, footer-sized glyphs, hairlines between items, color-only hover. Narrow windows drop whole items |
| `PopoverPanel`, `PopoverPanelFootnote`, `.dsPopover(isPresented:)` | Orca's Resource Manager layout (glyph and title header, hairline, content) on the overlay backdrop |
| `CappedHeightScrollView` | Natural height up to a cap, then scrolls |
| `NativeMark`, `NativeLockup`, `.nightSky(isEnabled:)`, `NightlyMark` | Native's brand: the interlock emblem from the app icon, the wordmark, and the nightly sky and moon |
| `LaunchAnimationView`, `.launchScreen(isPresented:)` | The emblem tracing in and interlocking while agents start |

## Patterns: use these, don't invent new ones

| Situation | Use |
| --- | --- |
| A failure | `ErrorState(what, recovery: what Native did, suggestion: what you can do, details:, primary:)`, `.inline` or `.pane` |
| Any other inline notice (offline, sign-in expired) | `NoticeBanner(tone:title:detail:) { one action }` |
| Nothing to show | `EmptyStateView(what, systemImage:, message: why, actionTitle:, action:)` |
| Something that can be taken back | `.undoToast($item)` with `UndoToastItem(message) { undo }`, instead of a confirmation |
| Usage limits | `LimitStatus` (one value from Usage), rendered by `LimitBanner` and `LimitChip`, worded by `LimitStatus.line(now:)` |
| Task state | `TaskStatus` + `StatusIndicator`; paused and limited included |
| Loading | `DotGridLoader`, never ad-hoc spinners |
| Something blocked on the user, in chrome | `.statusBarSegment(.attention)`: the only boxed item in the status bar, one at a time |
| Details on click | `.dsPopover` with a `PopoverPanel` |
| Elapsed time | `ElapsedTimeText(since:until:)`: ticks while running, a total once done |
| Counts, sizes, times | `DSFormat`: `compactAge`, `time`, `countdown`, `timeAndCountdown`, `duration`, `thoughtFor`, `tokens`, `percent`, `share`, `lineCount`, `diffStat`, `cost`, `memory`, `cpu` |

## Do and don't

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
