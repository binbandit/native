# Home Next shared components verification

Source revision: `02e7b9ecb426158f1ab55954bcd5c7ef825cdf17`. Isolated Debug instance: `rd-home-3`. `NativeHomeNext` enabled for checks and still default-off in production. Inert fixture content only; no real agent sessions or project changes.

Screenshots use a 1440 by 900 logical window, except the narrow fixture at 820 by 900. The optional status bar is hidden to match the approved reference. The reference is `home.html` from the approved Home design. Each theme was checked on the running app; captures do not measure animation timing.

## Approved reference comparisons

The shared command explainer determines the actual command consequences and hold behavior. The exact plan proposal is preserved as prose alongside its checklist. The managed fixture names the organization and reflects existing managed permission-mode and remote-host restrictions. Central policy does not yet expose universal command approval or GitHub availability.

### Dark

| State | Approved reference | Native |
| --- | --- | --- |
| Busy | <img src="mock-busy-dark.png" width="420"> | <img src="app-busy-dark.png" width="420"> |
| Every optional module off | <img src="mock-calm-dark.png" width="420"> | <img src="app-calm-dark.png" width="420"> |
| Managed by an organization | <img src="mock-org-dark.png" width="420"> | <img src="app-managed-dark.png" width="420"> |
| Plan approval | <img src="mock-plan-dark.png" width="420"> | <img src="app-plan-dark.png" width="420"> |
| Failed task | <img src="mock-failure-dark.png" width="420"> | <img src="app-failure-dark.png" width="420"> |
| All caught up | <img src="mock-quiet-dark.png" width="420"> | <img src="app-quiet-dark.png" width="420"> |
| First launch | <img src="mock-first-dark.png" width="420"> | <img src="app-first-dark.png" width="420"> |
| Allowed receipt | <img src="mock-allowed-dark.png" width="420"> | <img src="app-allowed-dark.png" width="420"> |
| Instruction entry | <img src="mock-reject-dark.png" width="420"> | <img src="app-instruction-dark.png" width="420"> |
| Shared sidebar | <img src="mock-sidebar-dark.png" width="420"> | <img src="app-sidebar-dark.png" width="420"> |

### Light

| State | Approved reference | Native |
| --- | --- | --- |
| Busy | <img src="mock-busy-light.png" width="420"> | <img src="app-busy-light.png" width="420"> |
| Every optional module off | <img src="mock-calm-light.png" width="420"> | <img src="app-calm-light.png" width="420"> |
| Managed by an organization | <img src="mock-org-light.png" width="420"> | <img src="app-managed-light.png" width="420"> |
| Plan approval | <img src="mock-plan-light.png" width="420"> | <img src="app-plan-light.png" width="420"> |
| Failed task | <img src="mock-failure-light.png" width="420"> | <img src="app-failure-light.png" width="420"> |
| All caught up | <img src="mock-quiet-light.png" width="420"> | <img src="app-quiet-light.png" width="420"> |
| First launch | <img src="mock-first-light.png" width="420"> | <img src="app-first-light.png" width="420"> |
| Allowed receipt | <img src="mock-allowed-light.png" width="420"> | <img src="app-allowed-light.png" width="420"> |
| Instruction entry | <img src="mock-reject-light.png" width="420"> | <img src="app-instruction-light.png" width="420"> |
| Shared sidebar | <img src="mock-sidebar-light.png" width="420"> | <img src="app-sidebar-light.png" width="420"> |

## Additional states and actions

| State | Dark | Light |
| --- | --- | --- |
| approvalFailure | <img src="app-approvalFailure-dark.png" width="420"> | <img src="app-approvalFailure-light.png" width="420"> |
| choice-failed | <img src="app-choice-failed-dark.png" width="420"> | <img src="app-choice-failed-light.png" width="420"> |
| destructive | <img src="app-destructive-dark.png" width="420"> | <img src="app-destructive-light.png" width="420"> |
| empty | <img src="app-empty-dark.png" width="420"> | <img src="app-empty-light.png" width="420"> |
| expanded | <img src="app-expanded-dark.png" width="420"> | <img src="app-expanded-light.png" width="420"> |
| failurePaused | <img src="app-failurePaused-dark.png" width="420"> | <img src="app-failurePaused-light.png" width="420"> |
| instruction-failed | <img src="app-instruction-failed-dark.png" width="420"> | <img src="app-instruction-failed-light.png" width="420"> |
| instruction-sent | <img src="app-instruction-sent-dark.png" width="420"> | <img src="app-instruction-sent-light.png" width="420"> |
| loading | <img src="app-loading-dark.png" width="420"> | <img src="app-loading-light.png" width="420"> |
| more | <img src="app-more-dark.png" width="420"> | <img src="app-more-light.png" width="420"> |
| narrow | <img src="app-narrow-dark.png" width="420"> | <img src="app-narrow-light.png" width="420"> |
| peek-choice-failed | <img src="app-peek-choice-failed-dark.png" width="420"> | <img src="app-peek-choice-failed-light.png" width="420"> |
| peek-instruction-failed | <img src="app-peek-instruction-failed-dark.png" width="420"> | <img src="app-peek-instruction-failed-light.png" width="420"> |
| planRetained | <img src="app-planRetained-dark.png" width="420"> | <img src="app-planRetained-light.png" width="420"> |
| planText | <img src="app-planText-dark.png" width="420"> | <img src="app-planText-light.png" width="420"> |
| question | <img src="app-question-dark.png" width="420"> | <img src="app-question-light.png" width="420"> |
| question-failed | <img src="app-question-failed-dark.png" width="420"> | <img src="app-question-failed-light.png" width="420"> |
| questionFailure | <img src="app-questionFailure-dark.png" width="420"> | <img src="app-questionFailure-light.png" width="420"> |
| questionText | <img src="app-questionText-dark.png" width="420"> | <img src="app-questionText-light.png" width="420"> |
| questions | <img src="app-questions-dark.png" width="420"> | <img src="app-questions-light.png" width="420"> |
| recovery | <img src="app-recovery-dark.png" width="420"> | <img src="app-recovery-light.png" width="420"> |
| unknown | <img src="app-unknown-dark.png" width="420"> | <img src="app-unknown-light.png" width="420"> |

## Validation

- Isolated Debug build and zero-repository-warning check.
- Home Next and Task Peek regression harnesses: exact and stale requests, child routing, shortcut ownership, acknowledged receipts, repeated failed choices and instructions, preserved draft and queue.
- `HomeAskOrderTests`: five passing package tests.
- Swift strict formatting lint on changed files, ShellCheck on both harness scripts, and diff whitespace checks.
- Live actions in both themes: instruction and Allow receipts; plan Show more opens shared Peek; Escape dismisses it; completed-task Show more; failed Home and Peek choices keep the instruction and ask; failed instruction retries preserve input; failed questions preserve their answer; sidebar titles suppress duplicate asks; disabling the switch restores the original Home.
- A targeted app iPad typecheck is blocked by the existing unconditional AppKit import in `native/Terminal/Settings/TerminalImportSheet.swift:1`. This file is unchanged by this PR. The standard iOS workflow is checked separately.

## Remaining Home work

- Shared New Task field.
- Optional review, usage-limit and away summaries.
- Central policy support for per-command approval and GitHub availability before promising the strictest enterprise mock behavior.
