# Agent switching review

Visual check pending

Screenshot revision: `f4c9de0007be2a9641db232e7b92ff9f30a00cc8`, isolated Debug instance `cx-agent-switch-findable`, 1100 x 850, sound disabled. All providers in these captures are offline ACP fixtures.

The control names the current harness and model. The first picker section shows installed agents with a check on the current one. Two and four agents fit one line. Models and filtering are scoped to the current agent. Both composers use the existing reversible, non-executing handoff. The Change Agent Labs switch still gates switching.

The approved design files were updated before implementation: `popover-spec.md` and `popover.html` in the shared claude-design folder. Mock states are `switch2`, `switch4`, `legacy2`, `legacy4`, with `theme=light|dark` and `closed=1` for controls at rest.

| Fine print | Agents | Appearance | Control screenshot | Popover screenshot | Matching mock |
| --- | --- | --- | --- | --- | --- |
| On | 2 | light | [next-2-light-control.png](next-2-light-control.png) | [next-2-light-popover.png](next-2-light-popover.png) | [switch2, light](mock-switch2-light.png), [control](mock-switch2-light-control.png) |
| On | 2 | dark | [next-2-dark-control.png](next-2-dark-control.png) | [next-2-dark-popover.png](next-2-dark-popover.png) | [switch2, dark](mock-switch2-dark.png), [control](mock-switch2-dark-control.png) |
| On | 4 | light | [next-4-light-control.png](next-4-light-control.png) | [next-4-light-popover.png](next-4-light-popover.png) | [switch4, light](mock-switch4-light.png), [control](mock-switch4-light-control.png) |
| On | 4 | dark | [next-4-dark-control.png](next-4-dark-control.png) | [next-4-dark-popover.png](next-4-dark-popover.png) | [switch4, dark](mock-switch4-dark.png), [control](mock-switch4-dark-control.png) |
| Off | 2 | light | [legacy-2-light-control.png](legacy-2-light-control.png) | [legacy-2-light-popover.png](legacy-2-light-popover.png) | [legacy2, light](mock-legacy2-light.png), [control](mock-legacy2-light-control.png) |
| Off | 2 | dark | [legacy-2-dark-control.png](legacy-2-dark-control.png) | [legacy-2-dark-popover.png](legacy-2-dark-popover.png) | [legacy2, dark](mock-legacy2-dark.png), [control](mock-legacy2-dark-control.png) |
| Off | 4 | light | [legacy-4-light-control.png](legacy-4-light-control.png) | [legacy-4-light-popover.png](legacy-4-light-popover.png) | [legacy4, light](mock-legacy4-light.png), [control](mock-legacy4-light-control.png) |
| Off | 4 | dark | [legacy-4-dark-control.png](legacy-4-dark-control.png) | [legacy-4-dark-popover.png](legacy-4-dark-popover.png) | [legacy4, dark](mock-legacy4-dark.png), [control](mock-legacy4-dark-control.png) |

Side-by-side review boards: [Fine print light](comparison-next-light.png), [Fine print dark](comparison-next-dark.png), [legacy light](comparison-legacy-light.png), [legacy dark](comparison-legacy-dark.png). All eight states and both controls per state were inspected. The native system popover adds its platform chrome around the 380pt content; the reference shows its HTML approximation. Existing legacy model badges, search and effort controls remain in their established style.

Verification:

- Debug build and changed-file strict formatting lint passed. No repository warnings.
- ACP: 20 focused Swift Testing tests passed, including three grouping tests. The regression first failed with a foreign model appearing in the current list.
- NativeCommands: 23 focused tests passed, including documentation consistency and shortcut conflicts.
- `scripts/tests/agent-model-change.sh cx-agent-switch-findable`: three completed runs passed. Covers the direct agent choice with Fine print off, default model selection, draft and attachment preservation, no working prompt, cancellation, failures, restart recovery and Undo.
- `scripts/tests/composer-settings.sh cx-agent-switch-findable`: passed, including the first Agent section and complete model-scope replacement.
- `drive.sh` through both composers: selected Codex, observed Codex-only models and the same draft, then Undo returned to Claude Code. The fixtures recorded zero `session/prompt` calls.
- The full matrix was driven through the isolated app. Screen lock was checked before each capture. Some capture locations were covered by other windows; the changed controls and popovers are rendered and readable. No other app was raised or controlled.
- Task menu commands that require the active app cannot be activated by the background driver. The registered Switch Agent command and its Agent-section request were exercised in the regression harness. The shortcut is Control-Option-Command-A.

Permission mapping is unchanged here and remains the responsibility of #222. Coordinator design review is required; do not merge this PR automatically.

Final follow-up revision: `0b5c6a73ce226b76acf5ae447d5603812f627537` (keyboard routing and regression harness). The resting layouts are unchanged from the screenshot revision. The final Debug build passed with no repository warnings, and both non-UI app regression harnesses were rerun successfully. The 20 ACP and 23 shortcut tests also pass on the final tree.

Pullfrog's Tab finding was reproduced on the screenshot binary: 20 Tab presses left Search models focused. Follow-ups return Tab to native traversal, remove the extra focusable container, and limit custom key handling to the focused search field. `scripts/tests/agent-switch-keyboard.sh` checks forward/backward footer access and Fast mode activation. Its after-check has not passed through the background driver: focus stayed in Search models. Some attempts were unavailable because the window was off screen, and the Mac is now locked. No raise, activation, global keyboard setting change or Space switch was attempted. Keyboard verification remains pending for the coordinator. See [before focus](keyboard-before-focus.txt) and [latest after focus](keyboard-after-focus.txt).

The local iPad folder check failed in shared platform dependencies, including AgentProcess, LocalCommandRunner, LocalStdioLauncher, and the ContextIndicator adapter. Those implementations and failing calls are unchanged from main. The check did not establish iPad verification for this change. See [diagnostics](ipad-check.txt). Release/Nightly compile checks were explicitly requested on the PR branch.

The final follow-up also skips the keyboard Model target for agents that offer no model setting, matching the visible picker content. Final CI/review status is reported on the pull request.
