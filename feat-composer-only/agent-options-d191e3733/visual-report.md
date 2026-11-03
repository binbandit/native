# Agent options in the composer menu

Revision: d191e3733907a6abcebaafe0fa2a937d8dc5413d, based on bbbcd1b7a. No working-tree changes after verification.

Visual check pending. The coordinator's design review and build-Mac interaction check are still required. No live app was launched or driven on this Mac.

## State inventory and references

All four PNGs render the actual menu and fixture sources through scripts/dev/render-previews.py. The local render.py wrapper supplies the existing ACP and AppAppearance package modules and objects to swiftc; it does not import the built app or replace any views. Screen lock was checked immediately before rendering and the renderer independently checked it. Both checks reported unlocked. The harness exited after rendering.

| State | Local screenshot under ~/native-work/shots/cx-composer-agent-options/ | Published screenshot | Matching reference |
| --- | --- | --- | --- |
| Agent offers Fast mode and Response style, light and dark | preview-1-light.png; preview-1-dark.png | [Paired comparison](preview-1-light.png) | Agreed composer-spec.md, Menus: extras in a short section under that agent's models |
| Agent offers no extra options, light and dark | preview-1-light.png; preview-1-dark.png | [Paired comparison](preview-1-light.png) | Existing Agent and model menu baseline from PR #273; no extra section |
| Existing searchable multi-agent catalog, light and dark | preview-0-light.png; preview-0-dark.png | [Existing catalog](preview-0-light.png) | Unchanged PR #273 menu layout and composer-spec.md, Menus |

In preview-1, the light pair is on the left and the dark pair is on the right. Within each pair, the left menu offers extras and the right menu does not. Inspected both appearance passes: option labels align with the model labels, current values align with their chevrons, all rows use the existing height and tokens, and the separator appears only with extras. The composer row has no new control. No exact mock for this newly approved menu section was provided; the agreed written specification and existing no-extras menu are the references, rather than a claimed pixel match to an unavailable mock.

## Verification

- Debug: scripts/dev/run-isolated.sh cx-composer-agent-options --build passed. scripts/check-warnings.sh reported no repository warnings.
- Regression: scripts/tests/composer-row-settings.sh cx-composer-agent-options passed all eight checks. Local ACP pipes exercised the real adapter and SessionModel action path without providers or app windows. This includes agents with no extras; extras from captured gateway data; uncategorized select options; two controls sharing a category; unsupported kinds; exclusion of dedicated model, effort, mode and Plan controls; ordered requests by option ID; confirmation in refreshed state; and invalid selections producing no requests, conversation or handoff.
- Before: compiled the same regression harness with the adapter source from bbbcd1b7a and the current app library. The existing seven checks passed, and the extra-settings presentation check failed because the before adapter omitted the extra settings. This is an adapter-level reproduction, not a full before-app UI run.
- Strict Swift lint on all six edited Swift files and git diff --check passed.
- Render: python3 /tmp/cx-composer-agent-options/render.py compiled the actual source previews in light and dark, producing the four PNGs above. The wrapper is included here for reproduction after rebuilding the isolated instance.
- Current branch includes origin/main. No files added or removed in the product change.

Status: partial. Rendering and the real model action path pass; interaction with the nested menus was not driven on this Mac, as instructed.

## Ownership follow-up

Pre-send generic choices need work in native/NewTask before they can be exposed safely in the unsent composer. ComposeTaskModel.choose currently requires a category and stores picks by category; addressedChoices snapshots only model, thought_level and mode. A follow-up must preserve generic choices by option ID through draft preparation, held drafts and task start. This change leaves that area untouched under the ownership rule and exposes the agent-reported settings on connected tasks only.
