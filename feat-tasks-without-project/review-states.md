Supplemental real-agent verification at `dab8f656`: Claude Code, Haiku 5.5, Low effort. The task wrote a file in its own scratch folder, moved with a byte-identical copy, kept its draft, and answered the follow-up with the same filename. Undo restored its row in both appearances. The final deletion check exposed an ordering bug, fixed in the subsequent revision; these Undo screenshots do not establish final cleanup.

| State | Dark app | Light app | Matching mock |
| --- | --- | --- | --- |
| Private task | [app](review-private-dark.png) | See original n4 | n4 |
| Move review | [app](review-move-dark.png) | [app](review-move-light.png) | n5 |
| Continued conversation | [app](review-moved-dark.png) | [app](review-moved-light.png) | n7 |
| Delete with Undo | [app](review-delete-dark.png) | [app](review-delete-light.png) | n9 |

[All eleven states with paired light and dark mocks](states.md).
