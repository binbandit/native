# Composer spec follow-up

Visual check pending

Revision: `bbbcd1b7aacc87852ea13ea6099cf58aae1875f9`. Before: `3904b63fb7fd4add45e98f7b1560932c4d37019b`.

The Where menu now belongs only to the unsent new-task composer with a project. Existing sessions offer no locations in idle, working or disconnected phases. A stale location action cannot change an existing session. The reserved row slot remains, preserving control alignment. Attachment and quote preview widths retain their original 560 and 420 values through `DS.ComposerField.attachmentPreviewWidth` and `.quotePreviewWidth`.

No exact mock image was supplied for this job. References are the agreed `composer-spec.md` (Shape and Menus), and the existing attachment/quote preview bodies at the before revision. Each attached image is a real SwiftUI render with light on the left and dark on the right. These are previews, not a live app test.

| Changed state | Screenshot | Matching mock/reference |
| --- | --- | --- |
| New task with Where; existing idle, working and disconnected tasks without Where, 720 points | [locations-720-pair.png](locations-720-pair.png) | Composer spec: Menus, Where is new-task only; Shape, fixed control row |
| The same four states at 600 points | [locations-600-pair.png](locations-600-pair.png) | Same spec; existing `DS.ComposerRow.narrowPreviewWidth` |
| Attachments accepted, pending, missing, selected and path-only, 560 points | [attachments-560-pair.png](attachments-560-pair.png) | Existing `ComposerAttachmentsSection` preview at `3904b63fb`, with the same width |
| Diff and output quotes, long source and four-digit line numbers, 420 points | [quotes-420-pair.png](quotes-420-pair.png) | Existing `ComposerQuotesSection` preview at `3904b63fb`, with the same width |

## Checks

- `git pull --ff-only`; `git fetch origin main`; `git rebase origin/main` passed. A final fetch confirmed zero new main commits to incorporate.
- Before the fix, `scripts/tests/composer-row-settings.sh cx-fix-273-spec` failed with `An existing task must not offer Where in idle`.
- `scripts/dev/run-isolated.sh cx-fix-273-spec --build` passed before and after the change. `scripts/check-warnings.sh /tmp/native-dd/cx-fix-273-spec/build.log` reported no repository warnings.
- After the fix, `scripts/tests/composer-row-settings.sh cx-fix-273-spec` passed all seven checks on three consecutive runs. See [row-checks.txt](row-checks.txt).
- `swift format lint --strict` passed for all five changed Swift files. `git diff --check` passed.
- `scripts/check-ios.sh native/Composer/ComposerRowModelAdapter.swift` stopped before checking the composer: the shared NativeDiagnostics/Sentry precompiled module references a modified header. Xcode also reported an out-of-date CoreSimulator runtime. No shared cache or simulator was changed.
- `scripts/dev/render-previews.py` rendered the actual views and the actual model adapter values from the isolated Debug build. The [compiler shim](render-xcrun) makes that build's modules available and adds `@testable import Native` to staged source files. The [location fixture](LocationPreviews.swift) hosts the real `ComposerBottomRow`; no replacement views are used. Previews are inert and create no agent session or window on screen. Screen lock checks reported unlocked before rendering.

Rendering commands, with the shim installed as `xcrun` on a temporary PATH:

```sh
scripts/dev/render-previews.py research/cx-fix-273-spec/LocationPreviews.swift /tmp/cx-fix-273-spec-previews/after/locations
scripts/dev/render-previews.py native/Composer/Sections/ComposerAttachmentsSection.swift /tmp/cx-fix-273-spec-previews/after/attachments
scripts/dev/render-previews.py native/Composer/Sections/ComposerQuotesSection.swift /tmp/cx-fix-273-spec-previews/after/quotes
```

## Remaining scope and limits

Item 3 is deferred under the brief's explicit fallback. `ComposerView.fieldSurface` still owns `fieldRequests`, which hosts the shared `SessionApprovalView` and `SessionQuestionView` above the queue and editor. Moving them into the transcript needs coordinated changes to the frozen task/transcript area: both `SessionView` and `SessionToolsScreen`, primary-transcript response ownership, scrolling, and the existing `wantsComposerFocus` routing. Reuse those same views and remove the composer presentation when that follow-up is assigned; do not create a second card family. The draft remains in the existing editor. Its live focus behavior was not exercised here.

Two existing preview issues were observed and left outside this small fix: four-digit quote line numbers wrap at the existing 420-point preview width; the renderer's second appearance pass collapses the capped attachment/quote scroll content. The attached first-pass paired captures contain both complete light and dark states. An initial location fixture mutated observed session state during layout; it was stopped and replaced by the inert fixture linked above, after which all location captures completed.

No live app was driven on this Mac. Live input, focus, queue and Quick Entry validation remain with the build-Mac job. Design review and CI remain pending. No new motion or product copy was introduced. App-branch files added: none. Removed: none. Five existing files changed: the row adapter, the two section previews, composer field tokens and the existing row regression harness.
