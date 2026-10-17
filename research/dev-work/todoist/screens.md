# Todoist (iOS)

App id `572688855`. $400K/mo, 4.8 stars. 33 screens; studied the **Task Management** flow only (7 screens,
`list_app_screens(flow="Task Management")`) on 2026-10-17. Onboarding (15) and settings skipped: they don't
bear on Native. Re-fetch with `get_screen(screen_ref="572688855/<id>")`.

Why: the reference for a calm, dense task list on a phone, and for a task detail sheet with its actions.

| Screen id | Name | What's notable |
| --- | --- | --- |
| oth_rv5eb | Today Empty | Large title; illustration + one bold line + one line saying how to fill it ("tap + to add"); help glyph bottom-left; red FAB |
| oth_qlw7c / oth_2fpr5 | Today Task List | Date section label; row = ring checkbox tinted by priority, title, project name right-aligned on a second line; hairline separators; floating pill tab bar (Inbox, Today, Upcoming, Browse) with the active tab in a tinted pill |
| oth_eu6fo | Task Details | Sheet over the dimmed list: X and `...`; ring + title; metadata rows (project, date, priority flag); property chips (Description, Reminders, Labels); Sub-tasks; Comment field pinned to the bottom |
| oth_a2ew3 | Task Actions Menu | Popover headed by a timestamp caption ("Added on ..."); Edit, Duplicate, Copy link, Email, Show completed, View activity; divider; Delete in red |
| oth_1bcpq | Upcoming | Week strip with selected day badge |
| oth_osnlj | Browse | Profile pill, bell, gear; Try Pro row; Search / Filters / Reporting; My Projects |

Takeaways
- One status glyph per row, colored by what matters (priority), nothing else competes.
- Secondary metadata goes right-aligned on a second line in tertiary text.
- Detail = sheet over the list (context stays visible), comment/reply field pinned at the bottom.
- Overflow menus open with a quiet provenance caption (when/where it came from) before the actions.
