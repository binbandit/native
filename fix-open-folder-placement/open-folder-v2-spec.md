# Open Folder v2

Supersedes section 1 of requests-1026-spec.md and requests-1026.html. The approved product decision removes the permanent footer action and its recents disclosure.

## Composition

Use `SidebarSectionLabel("Projects")` above the project groups. Its 12pt semibold Geist, -0.06 tracking, secondary text, 30pt leading and 10pt trailing insets are exactly the shared All in view heading. Use the existing small `IconButton` with a regular 12pt plus in a 24pt square, radius 4. Secondary at rest, primary with the existing 4.5% neutral hover wash. Keep the control visible at rest and on touch. Give the heading at least the platform minimum target height and preserve `.dsHitTarget` on the control. No new color, size or animation token.

The plus opens the chooser directly through `requestOpenFolder`, with the accessible name Open Folder… and Command-O tooltip. Disable during opening or when managed policy forbids additions. Keep the heading in place in both cases. The quiet plus does not compete with New Task; folder-level plus buttons still create tasks.

The footer contains only the existing account and Settings controls. Keep opening, failure, managed and Added/Undo feedback. File > Open Recent remains the home for recents. Command-O, File > Open Folder and folder drops keep their model behavior. The entire sidebar is a folder drop target, including its footer; private internal drags still reorder.

Compose page, Home start address and Quick Entry use the same project list. Its final action is **Open Folder…**, after the separator. Keep the draft and existing chooser destination behavior. Respect managed admission and opening state. The no-project Home retains **Choose a folder / Open the project you want to work in.**, one primary **Open Folder…** button and the drop hint. The sidebar's empty list remains quiet guidance.

## Palette and typography

Reuse Standard dark: content #0D0D0E, sidebar #070708, secondary #A5A5A8, primary #E9E9E6, tertiary #85858A. Paper light: content #FBFBFB, sidebar #F0F0F0, secondary #505050, primary #181818, tertiary #8D8D8D. These are DesignSystem tokens, not feature literals. Geist is used throughout; Geist Mono appears only for shortcut keycaps and existing metadata. No decorative treatment or glass is added.

## State matrix

`open-folder-v2.html?only=<state>&theme=light|dark` opens a 1000 by 700 mock. The default pairs light and dark.

| State | Review |
| --- | --- |
| rest | Plus sits on the shared trailing control edge; no footer action |
| hover | Existing IconButton hover wash, with no movement or row highlight |
| picker | Final Open Folder… item in Compose, Home and Quick Entry |
| empty | One primary action in the main empty state |
| drop | Existing neutral drop outline and release guidance across the sidebar |
| touch | Plus visible without hover, 44pt target |
| blocked | Disabled plus, policy explanation retained |
| opening | Disabled plus, existing opening feedback retained |

## Design review

Compared with sidebar.html All in view, merged #89, #135 and #192, and the shared SidebarSectionLabel, AllInViewProjectGroup and IconButton source. The control reuses the exact shared component; adding a custom folder glyph, capsule, footer row or separate recents control would introduce competing structure. Existing project/task text remains on the same 38pt window edge. Both appearances use existing colors. Review screenshots beside matching mocks before the separate coordinator design review. Native hover, external drag and iPad touch require real-surface evidence or an explicit coverage limit; fixture screenshots are labeled as such.
