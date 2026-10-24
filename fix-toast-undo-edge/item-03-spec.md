## 03 Undo, as the toast's edge

**PR:** `fix(ui): make Undo the undo toast's trailing edge, with its key`

### What's wrong today

1. Undo is a 24pt outlined `.ds(.secondary)` box inside an outlined toast, 8pt from its top and bottom but 16pt
   from its left: a box in a box, wedged in.
2. Undo and the X sit side by side at nearly equal weight, for a toast with one thing worth clicking.
3. ⌘Z undoes archive, rename, pin and delete (`docs/keyboard.md`), and the toast never says so.
4. Bottom trailing, 24pt in, it covers the composer's model and send button in any window under about 1,780pt
   wide (sidebar open), for five seconds.
5. Its timer keeps running while the pointer is on it.

### Anatomy and tokens

| Part | Spec |
| --- | --- |
| Toast | Width 356 (as today, shared with `ProjectActionToastView`), min height 40, `RoundedRectangle(cornerRadius: DS.Radius.card)` (8), `.dsOverlayBackground`, `strokeBorder(.dsSeparator, lineWidth: 1)`, `.dsShadow(.modal)`, `HStack(spacing: 0)`. |
| Message | `.dsBody`, `.dsTextPrimary`, `DS.Tracking.tight`, `lineLimit(3)`; padding leading `DS.Space.xl` (16), trailing and vertical `DS.Space.lg` (12). |
| Divider | 1pt `.dsSeparator`, full height. |
| Undo zone | Full height, padding horizontal 14, `HStack(spacing: DS.Space.sm)`: "Undo" in `.dsBodyMedium` primary, then `Kbd("⌘Z", style: .plain)`. Wash `.dsHover` hovered, `.dsPressed` pressed, shaped `UnevenRoundedRectangle(bottomTrailingRadius: 8, topTrailingRadius: 8)`; `.dsFocusShape` on the same shape. |
| `Kbd(.plain)` | New style on `Kbd`: no cap or outline; Geist Mono 10 with the modifier glyph from the system font; `.dsTextTertiary`. |
| Close | 18pt circle centered 2pt inside the toast's top-leading corner (so it sits 7pt outside), `.dsSurfaceRaised`, 1pt `.dsBorder`, `.dsShadow(.drag)`; `xmark` `.system(size: 7, weight: .bold)` `.dsTextSecondary`, primary hovered. Shown while the pointer is over the toast or focus is in it (opacity in `.dsQuick`); always on touch platforms. |

### Behavior

- **⌘Z on Undo only when ⌘Z takes back the same change.** `UndoToastItem(_ message:, undoesWithCommandZ: Bool =
  false, undo:)`. True from `RootView`'s `offeredUndo` (archive, rename, pin, delete), Celebrations' bulk changes
  and Hosts' remove (verify each registers with the window's `UndoManager`). GitHub's toasts (resolve, delete
  comment, merge queue, auto-merge, close/reopen) stay false.
- **Hover holds it.** While the pointer is on the toast it stays; leaving resumes with max(remaining, 3s).
- **Above the composer.** It keeps its corner (bottom trailing, `DS.Space.xxl` in) and adds the composer's
  height + `DS.Space.lg` to its bottom padding whenever the composer is under it. `SessionView` publishes its
  bottom bar's height with a preference (`UndoToastBottomInset`), read by `UndoToastSlot`. Pages without a
  composer are unchanged.
- **After Undo** the toast leaves: opacity and 4pt down in `.dsPanel`. Arrival unchanged
  (`.move(edge: .bottom)` + opacity, `.dsPanel`). Reduce Motion: opacity only.
- Escape doesn't dismiss it (Escape stops the turn in a task).

### Accessibility and touch

- One element; the message is announced (as today), not focused. Actions: "Undo" and "Dismiss", so the hidden
  close is always reachable.
- iPad (`DS.isTouchPlatform`): the close button is always shown; a downward swipe dismisses.

### States to preview

Rest (two lines), hover (zone wash and close), pressed, keyboard focus, one line, without ⌘Z, three lines,
iPad. Dark and light in `DSPreviewPair`.

### Files

`native/DesignSystem/Patterns/UndoToast.swift`, `native/DesignSystem/Components/Kbd.swift`,
`native/Views/RootView.swift` and `native/Views/SessionView.swift` (the inset preference), and the call sites
that pass `undoesWithCommandZ`.

**Not in it:** `ProjectActionToastView`'s steps (two steps and a detail line; its own change later). No
enterprise state: a toast carries no setting.

