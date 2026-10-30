# Warm worktrees evidence

Revision: `ecd4379d4725a960fb1b5bcf2236f0c041efce4f`. Base: `5fd6e789e38ad8dd1c32f0c85f254fccc1b332de`. Revision details and Debug binary SHA256 are in [revision.json](revision.json). Screenshots and timings were captured before a documentation/dev-tool-only main rebase; native and Packages source-tree identities are recorded and unchanged.
Isolated instance: `cx-warmwt`. Sound disabled. Fixture data only.

## Timing method

One cold task and one warm task per fixture, in the running Native app. Cold uses today's behavior with the Labs switch off; warm enables Warm Worktrees with the default folder list and env off. Both use the same project Setup command, `./verify-build.py`. Time starts immediately before the pid-scoped New Task AX action and stops when the setup command records its first successful build. It includes worktree creation, cloning, and setup. The build column measures only setup's install/build subprocesses. It excludes model-turn latency. These are single local samples, not a large-project performance claim.

Each measured task used Claude Code, Haiku 5.5, effort Low, with a tiny `Reply OK.` smoke turn after preparation. Setup output stayed in the task banner. No dependency download was needed.

| Fixture mode | Task start to successful build | Install/build subprocesses | Exit status |
| --- | ---: | ---: | ---: |
| node-cold | 1.367 s | 0.653 s | 0 |
| node-warm | 1.415 s | 0.116 s | 0 |
| swift-cold | 4.057 s | 3.348 s | 0 |
| swift-warm | 3.394 s | 2.900 s | 0 |

Node: synthetic local tarball with 3,000 files, 12 MB installed cache, offline npm ci when dependencies are absent, npm run build. Warm tasks cloned node_modules and dist and skipped reinstalling. Total task startup was roughly unchanged on this small fixture despite the faster build step.
SwiftPM: dependency-free executable with 20 source parts, 18 MB .build cache, swift build -j 4. Warm tasks cloned .build, but SwiftPM rebuilt most targets after relocation. Cache cloning does not make path-sensitive compiler output portable.
Warm tasks had no .env file; both fixture sources contained a harmless .env. Unit tests separately verify env opt-in.

Sources: [Node fixture](node-fixture.tar.gz), [SwiftPM fixture](swift-fixture.tar.gz). Extract each into an empty folder, git init and commit its files, create a harmless untracked .env file if checking env consent, prime it with ./verify-build.py, add it as a Native project, and set that script as Setup. The Node script expects npm at /opt/homebrew/bin/npm. Toggle the Labs switch between task creations. Raw JSON results are adjacent to this page.

## Visual states

[Side-by-side comparison page](comparison.html). Mock references use Native's existing design-system patterns. The renderer substitutes static text for native text fields that ImageRenderer cannot capture. The setup editor reference is a static reference based on the existing editor layout, because ImageRenderer cannot capture its native editor and segmented control. Native disabled-control opacity can differ from these static references. This comparison is an implementation check; coordinator design approval is still pending.

| State | Running app screenshots | Matching reference |
| --- | --- | --- |
| Default, no setup | [light](settings-default-light.png), [dark](settings-default-dark.png) | [light](mock-default-light.png), [dark](mock-default-dark.png) |
| Setup configured | [light](settings-ready-light.png), [dark](settings-ready-dark.png) | [light](mock-ready-light.png), [dark](mock-ready-dark.png) |
| Copies off | [light](settings-disabled-light.png), [dark](settings-disabled-dark.png) | [light](mock-disabled-light.png), [dark](mock-disabled-dark.png) |
| Invalid folders and env opt-in | [light](settings-invalid-light.png), [dark](settings-invalid-dark.png) | [light](mock-invalid-light.png), [dark](mock-invalid-dark.png) |
| Setup editor | [light](settings-editor-light.png), [dark](settings-editor-dark.png) | [light](mock-editor-light.png), [dark](mock-editor-dark.png) |

Task preparation: [live light screenshot](task-ready-light.png), [live dark screenshot](task-ready-dark.png), compared with [ready light preview](notice-ready-light.png) and [ready dark preview](notice-ready-dark.png). The preview isolates the banner and the app screenshot includes its task context. The task screenshots crop the window title bar to omit generated local paths.

Additional rendered preview states, both schemes: [ready light](notice-ready-light.png), [ready dark](notice-ready-dark.png), [unsupported light](notice-unsupported-light.png), [unsupported dark](notice-unsupported-dark.png), [skipped light](notice-skipped-light.png), [skipped dark](notice-skipped-dark.png), [copy failure light](notice-copy-failure-light.png), [copy failure dark](notice-copy-failure-dark.png). These are fixture renders, not live off-APFS or failure reproduction. The no-copy fallback is forced in an Exec test; no real non-APFS volume was mounted.

The folder editor was exercised with a trailing comma followed by another entry, and with invalid parent/env paths. Copies-off leaves Setup enabled. Settings survive relaunch. Screens were unlocked before screenshots.

## Validation and limits

Package checks: `nice -n 10 swift test -j 4 --filter WorktreeCloneTests` (7 passed) and `nice -n 10 swift test -j 4 --filter WarmWorktreeTests` (3 passed). Isolated Debug build, repository warning check, setup integration harness and strict formatting passed. Release and Nightly compiled through the build-slot wrapper. Their installed sizes were 119.0 MB and 119.1 MB, and download sizes were 48.8 MB and 48.9 MB, within the existing budgets. See the PR for the final checks.

The iPad typecheck attempt expanded into unrelated app dependencies and reported existing plugin, host, MCP and terminal errors. It was stopped after about 31 minutes; it is not a passing check. None of the captured diagnostics names a changed warm-worktree file. [Captured diagnostics](ios-attempt-diagnostics.txt). The feature defaults off in Labs. No real non-APFS volume or paired iPad host was available for end-to-end cloning. Absolute interpreter links cause Python environment caches to be skipped; use setup to recreate them.

Follow-up: existing abandoned-draft cleanup treats ignored files as work. Warm caches can therefore retain otherwise empty draft worktrees. This PR preserves that deletion safeguard.
