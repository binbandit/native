# Composer rest and settings verification

Revision: `ffb4c3808cd42ea78e9937c1757851fc5726091d`, based on `1262168a4a8d09c057695604ddb155b60e424837`.

The isolated Debug instance used the committed local ACP fixture, with NativeComposerNext enabled. NativeTaskWell and NativeSidebarNext were also enabled. Screenshots contain fixture content only. The screen was unlocked for every capture. The background-only driver sometimes reported another window covering the instance; captured content was inspected, and state changes were also verified through AX and actual fixture ACP requests.

Both light and dark passed:

- Resting field and the one model-name control.
- Model, effort, permission, web-search and agent-option picks; actual values checked in the fixture.
- Shared MCP panel and return to settings.
- A rejected model change retains the previous choice, shows an inline error, and can be retried.
- Large model list search, selecting model 34, and no matches.
- No offered settings, with the agent-default and unavailable web-search explanations.
- A typed draft remains when changing the model.
- Narrow 560pt window, with the same native popover.
- Managed permission rows, lock labels, organization footer and enforced read-only mode.
- Startup loading and unavailable settings, using a local fixture copy that delays loading or returns a session/load error.
- Switch off: the previous controls and More menu remain, including web search and agent extras.

The focused ACP suites passed 21 tests; KeyboardDocumentTests passed five. Changed Swift files passed strict format lint. Debug built without repository warnings. Release and Nightly results are recorded in the PR.

The iPad check stops at the unchanged HostRegistration.swift import of ServiceManagement. Focus-dependent keyboard behavior cannot be conclusively verified by the background-only driver; the existing command path and keyboard document tests are covered.

Policy currently supports permission restrictions and MCP servers. Model restrictions, offline web-search policy and project-level source provenance need backing APIs in later slices.
