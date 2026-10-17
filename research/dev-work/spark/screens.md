# Spark Mail (iOS)

App id `997102246`. $200K/mo, 4.62 stars. 75 screens; studied the **Inbox** flow only (4 screens) on
2026-10-17. Re-fetch with `get_screen(screen_ref="997102246/<id>")`.

Why: the best inbox-triage grammar in the library, which maps onto "which agent tasks need me".

| Screen id | Name | What's notable |
| --- | --- | --- |
| oth_xm4na | Inbox (Focused list) | Time buckets (Today, Yesterday, This week, Last week); **bundles with counts** ("Notifications 576") showing their top senders as chips; unread = small blue dot in the left gutter; row = avatar, bold sender, subject, grey preview, time right |
| oth_bslc5 | Layout Picker | Three layouts as preview thumbnails (Focused list, Unread cards, Simple list) |
| oth_0hnj0 | Inbox (Simple list) | Same rows without bundles |
| oth_q2xik | Message Action Menu | Long-press lifts the row above a dimmed list and opens a menu: Reply, Forward, Priority, Set aside, Mark read, Pin, Snooze, Labels, Spam, Done, Move |

Takeaways
- Unread is a dot in the gutter, not bold everything.
- Low-value items bundle into one row with a count; high-value items stay individual.
- Time buckets beat a flat list for "what happened while I was away".
- Long-press = preview + every action; the row you pressed stays visible.
