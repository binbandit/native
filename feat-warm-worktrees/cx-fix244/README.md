# Project setup simplification

Design re-review for PR #244. Visual check pending.

The project section now has two rows under Dependencies and caches. The folder field is one full-width line, starts empty, and suggests common names as placeholder text. An empty list turns copying off, including env files. Existing saved opt-outs remain off. Env consent keeps its credential warning. Setup appears once, in Scripts, and says that it runs once per worktree while the agent waits. The background After creating a worktree hook remains distinct. Success reads `Copied node_modules, dist.`

## Rendered states and references

The following are actual SwiftUI previews rendered by scripts/dev/render-previews.py. Every image contains light and dark side by side; both outer appearances were also rendered. The old references are the baseline reviewed in the Design review: changes required comment. That comment intentionally supersedes their master switch, Setup location, multiline field and long copy. There was no revised visual mock supplied for the simpler layout.

| State | Light export | Dark export | Baseline mock / matching reference |
| --- | --- | --- | --- |
| Empty folders, env off | [light](preview-0-light.png) | [dark](preview-0-dark.png) | [default light](../mock-default-light.png), [default dark](../mock-default-dark.png), design review items 1-5 |
| Configured folders | [light](preview-1-light.png) | [dark](preview-1-dark.png) | [ready light](../mock-ready-light.png), [ready dark](../mock-ready-dark.png), design review items 1-5 |
| Invalid folders, env consent | [light](preview-2-light.png) | [dark](preview-2-dark.png) | [invalid light](../mock-invalid-light.png), [invalid dark](../mock-invalid-dark.png), retained warning and invalid-path note |
| Plainly settings | [light](preview-3-light.png) | [dark](preview-3-dark.png) | Existing SettingsRowGroup and settingsField patterns; no separate mock supplied |
| Narrow layout | [light](preview-4-light.png) | [dark](preview-4-dark.png) | Same two-row layout at 420 pt; no separate mock supplied |

The folder controls are the production WorktreeWarmProjectContent view used by WorktreeWarmProjectSection. Renderer support for the preview pair, page padding, environment keys and row ID was extracted verbatim from their source declarations; no replacement views or mock controls were used.

## Verification and remaining checks

Source revision: `c322a88ba2dde082e2734e69df7d7cfb221aa4f1`, rebased on origin/main `272dd76e3`. The isolated Debug build passed with no repository warnings. WarmWorktreeTests passed all four tests, including the regression for an empty folder list with env-file consent enabled. Strict Swift lint and diff whitespace checks passed. The existing worktree script integration check passed.

Scripts with Setup unset, Scripts with Setup configured, and task notices still need light and dark captures. Their production previews are present in ProjectScriptsSection.swift and TaskScriptSetupStrip.swift. Full-app folder editing, persistence, undo and Setup editor checks also remain pending: `/tmp/native-tools/screenlocked` reported `locked` after the folder previews were rendered. No blank captures were taken or substituted.

The Scripts rows use the existing Scripts settings pattern, and the success notice uses the existing task preparation strip. No separate revised mock was supplied for these states. The five folder-state captures above were inspected against the original references and the requested simpler layout. Independent design re-review remains pending.
