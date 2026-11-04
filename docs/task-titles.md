# Task names

Before this change, Native displayed a manual rename, then its own generated title, then the
agent-reported title, then the first-message fallback. The first enabled title plugin wins; the
built-in On-Device Titles plugin runs Apple's `SystemLanguageModel.default` through Foundation
Models, with greedy sampling and a guided title string. No remote model is selected for naming.
The title and custom instructions are independent of the model selected for the coding task.
The system prompt is [SessionTitlePrompt.builtIn](../Packages/AIInstructions/Sources/AIInstructions/SessionTitlePrompt.swift);
the guided output and sampling options are in
[OnDeviceTitleGenerator](../Packages/SessionTitling/Sources/SessionTitling/OnDeviceTitleGenerator.swift).

Generation starts alongside the first usable prompt. Only the project name and the first 2,000
characters of that message were supplied, never the agent's answer. Attachment names substitute
for an empty message. A generated title was accepted once, with no later improvement. A failed or
unavailable generator could retry once on the next ordinary turn, using the original message.
The offline fallback was the first eight words of the first nonempty line, plus an ellipsis.
The old prompt asked for 2 to 6 words naming the specific task but did not enforce that limit.

A user's rename always wins, including while generation is suspended. The host persists it and
clients protect pending renames while reconnecting. Clearing a manual title restores the automatic
one. Agent-reported titles never override a Native-generated name. An agent's own naming model
belongs to its adapter; Native does not choose that model. Agents with a plugin-provided rename
command receive Native's existing name before their prompt, avoiding their own naming turn when
that command does not use a model.

The current approach keeps the same provider order and on-device model. It prepares safe, bounded
input, asks for the main goal rather than a conversation summary, preserves technical spelling,
and strips low-value words from verbose answers. The first fallback appears without waiting for
the model. That temporary fallback is replaced once by the first generated title, which stays
final even when it is generic or the first turn later clarifies the task. While no generated name
exists, the request can keep the first turn's assistant answer for a pending attempt or retry.
Manual renames always win. Revision checks also prevent an older client's pending refinement from
replacing a generated title.

The existing plugin admission and managed instructions continue to apply: the organization's title
instructions replace project and global instructions. Turning off the provider prevents further
generation, including application of an in-flight title. There are no new dependencies,
endpoints or content logs. Naming does not open pasted files or links.

## Evaluation

`Packages/SessionTitling/Tests/SessionTitlingTests/Fixtures/tasks.json` contains 40 authored tasks,
synthetic first-turn outcomes, human reference names, and captured before/after titles. It includes
short requests, follow-ups, questions, pasted logs, links, multiple asks, and code in Swift,
TypeScript, Python, Rust, Go, Kotlin, Ruby, C# and C++. No personal session data was read.

The baseline was captured from commit `0257c27e36c71870e7357ca2de02bec6cb845545` on macOS 27.2
with Apple Intelligence available. A model refusal is recorded as an empty generated title and
scored using the old visible fallback. The newer capture used the previous state machine,
including a possible single refinement. Replays now keep the captured initial title when a
refinement was recorded, so those historical answers also check title stability. Model captures
use greedy sampling, but results can still change with OS/model updates. The checked-in replay is deterministic and offline; it tests rules
and transitions against those captured provider answers. It is not a claim that every future
on-device inference produces the same strings.

The historical capture scored **222/240 before and 239/240 with refinements**. Keeping the initial
names scores **235/240**: recognition stays at 35 tasks, and all 40 titles have 2 to 6 words, up
from 29. The replay reports each criterion so the stability tradeoff stays visible.

Each title gets one point per criterion: a fixture subject keyword, 2 to 6 whitespace-separated
words, sentence case, no filler prefix, no quotes/trailing punctuation, and no credential or path.
Reference names are guidance rather than exact-match expectations. Keyword scoring is deliberately
simple; it cannot prove that a title preserves every nuance of a request. The comparison table
in the PR includes every result so the semantic tradeoffs can be reviewed directly.

Run the offline evaluation and transitions:

```sh
nice -n 10 swift test --package-path Packages/SessionTitling -j 4 --filter 'TitleEvaluationTests|TitleRefinementTests'
```

Capture fresh model results locally, without network requests or personal data:

```sh
TITLE_CAPTURE=/tmp/task-title-capture.json nice -n 10 swift test --package-path Packages/SessionTitling -j 4 --filter TitleEvaluationTests
```

The app-owned retry regression runs against an isolated Debug build without opening a window,
starting an agent, or invoking the on-device model:

```sh
scripts/tests/session-titles.sh cx-better-titles
```

It holds a provider, disables titles while that request is suspended, releases the result, then
re-enables titles and sends a later prompt. It checks recovery and the unchanged retry budget.

The capture test is opt-in and skips in normal CI. Inspect fresh captures before updating fixtures;
do not overwrite the baseline with new-model results.
