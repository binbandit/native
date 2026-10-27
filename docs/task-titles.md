# Task names

Before this change, Native displayed a manual rename, then its own generated title, then the
agent-reported title, then the first-message fallback. The first enabled title plugin wins; the
built-in On-Device Titles plugin runs Apple's `SystemLanguageModel.default` through Foundation
Models, with greedy sampling and a guided title string. No remote model is selected for naming.
The title and custom instructions are independent of the model selected for the coding task.

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
the model. A weak name can be refined once using the original request and the first turn's
assistant answer. Short follow-ups require that context even if the initial model invented a
specific-sounding subject. A specific initial title stays. Manual renames block refinement even
if subsequently cleared. Revision checks reject stale answers and the host stores the budget.

The existing plugin admission and managed instructions continue to apply: the organization's title
instructions replace project and global instructions. Turning off the provider prevents further
generation, including application of an in-flight refinement. There are no new dependencies,
endpoints, content logs, file reads, or link fetches.

## Evaluation

`Packages/SessionTitling/Tests/SessionTitlingTests/Fixtures/tasks.json` contains 40 authored tasks,
synthetic first-turn outcomes, human reference names, and captured before/after titles. It includes
short requests, follow-ups, questions, pasted logs, links, multiple asks, and code in Swift,
TypeScript, Python, Rust, Go, Kotlin, Ruby, C# and C++. No personal session data was read.

The baseline was captured from commit `0257c27e36c71870e7357ca2de02bec6cb845545` on macOS 27.2
with Apple Intelligence available. A model refusal is recorded as an empty generated title and
scored using the old visible fallback. The new capture exercises the production state machine,
including a possible single refinement. Model captures use greedy sampling, but results can still
change with OS/model updates. The checked-in replay is deterministic and offline; it tests rules
and transitions against those captured provider answers. It is not a claim that every future
on-device inference produces the same strings.

The recorded score improves from **222/240 to 238/240**. Subject recognition improves from 35 to
39 tasks; titles with 2 to 6 words improve from 29 to 39. One result is still verbose.

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

The capture test is opt-in and skips in normal CI. Inspect fresh captures before updating fixtures;
do not overwrite the baseline with new-model results.
