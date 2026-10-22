# Search

Find any task by what was said in it: plain text across every agent run, every agent and every
project, archived tasks included as a filter. ⇧⌘F (Go ▸ Search Tasks…) or the magnifying glass in
the window toolbar, between the sidebar toggle and the history arrows, opens it. The button stays
available with the sidebar collapsed. Return opens the task scrolled to the exact message, highlighted.

The code: `Packages/Search` (UI-free, macOS and iOS, tested), the history readers in
`Packages/Search/Sources/Search/History` wired through each agent's plugin, and the app's part in
`native/Search/` (`TranscriptSearchCenter`, the panel, Settings ▸ Search).

## What's searchable

| Kind | Indexed as | Role |
| --- | --- | --- |
| The user's prompts | the whole message | `user` |
| The agent's replies | the whole message (first 24k characters) | `agent` |
| Reasoning | the summary or text (8k); left out of results unless asked for | `thought` |
| Tool calls | title, every string of the input (paths, commands, patterns, URLs, 2k), and the start and end of the output (2k) | `tool` |
| Plans | the latest plan's steps | `plan` |
| Task titles and project names | one document per task | `title` |

Tool output repeats whole files and logs, so only its first and last characters are kept: enough
to find "the run where `cargo test` said 3 passed", small enough that years of history stay a
modest file. Subagents' own transcripts aren't separate results; what they hand back shows in
their parent.

## Querying

Plain words match anywhere, every word must match, and the last word matches as a prefix while
it's being typed, from its third letter (`rollb` finds `rollback`; one or two letters would match
most of the index). Symbols are part of the text: `AppModel.swift`,
`git rebase -i` and `native/Models` search as written, as phrases. Quotes make a phrase.

Operators narrow without leaving the keyboard; the filter bar sets the same filters:

| Operator | Filter |
| --- | --- |
| `agent:codex` | agents whose id contains the text |
| `project:native` (or `in:`) | projects whose folder contains the text |
| `role:user` · `agent` · `tool` · `plan` · `thinking` · `title` | what kind of text matched (`thinking` also turns reasoning on) |
| `has:diff` | only tool calls that changed files |
| `is:archived` | include archived tasks |
| `after:2026-10-01` · `before:2026-10-31` | when it was said |

Only filters and no text lists the latest tasks that pass them (`agent:codex` alone shows the
latest Codex tasks).

## The index

SQLite FTS5 from the system's `libsqlite3` (no new dependency), one file per bundle id:
`Application Support/<bundle id>/search-index.sqlite`, so an isolated instance has its own.

```
sessions  (agent, session) unique · title · cwd · project · created_at · updated_at · archived
items     session_row → sessions (cascade) · ordinal · role · date · has_diff · anchor · body · parts
items_fts fts5(body, parts, content='items', tokenize='unicode61 remove_diacritics 2'), kept by triggers
sources   path · size · modified · offset · agent · session · cwd   -- one checkpoint per history file
meta      'filled' once a pass over the history has finished
```

- **Code-aware tokens.** `unicode61` already splits on everything that isn't a letter or digit, so
  `snake_case`, `kebab-case`, `a/b/c.swift` and `--flag` come apart into words. camelCase it can't
  split, so each item also stores its identifiers' pieces in `parts` (`SessionStore` →
  `session store`, `parseHTTPHeader` → `parse http header`). `body` keeps the text intact for
  phrases and snippets; queries match both.
- **Ranking.** `bm25(body 1.0, parts 0.4)`, times a recency boost (1.5× today, 1.25× at two weeks,
  fading to 1× over months), times a role weight (title 1.5, prompt 1.25, reply and plan 1.0, tool
  0.8, reasoning 0.6). Without narrowing filters, only the 4,000 best matches by text are
  weighed, so a word that's everywhere ("the") doesn't cost a lookup per match; with filters every
  match is weighed, so a rare one isn't missed. The best 600 hits are grouped by task, tasks ordered
  by their best hit, each showing its best three.
- **Snippets.** About 180 characters around the first match, whitespace collapsed, with every
  query word marked as a run, case- and diacritic-insensitively and inside identifiers (`model`
  lights up in `AppModel`). Built in Swift from the stored body, not FTS5's `snippet()`, which
  can't see matches that only hit `parts`.
- **Two connections.** WAL mode, one writer and one reader, so a search never waits on indexing.
- **It's a cache.** A schema change drops and refills it rather than migrating; clearing it in
  Settings is always safe.

## Keeping it filled

| Source | When | Notes |
| --- | --- | --- |
| Live sessions of agents with a reader | 3 s after a turn ends or fails (coalesced) | a pass that reads only the lines the turn added to the agent's log; never per streamed chunk |
| Live sessions of agents without one (or with history reading off) | 2 s after a turn ends or fails (coalesced) | the whole transcript from `SessionState`, converted off the main thread |
| Agents' own history | 2 s after launch, when enabled, and when the panel opens if the last pass was over 5 minutes ago | through each agent plugin's `SessionHistoryReader`, from each file's checkpoint |
| Agents without a reader | when the user opens one of their sessions and it has loaded | the loaded transcript, as for live sessions |

**History readers** are part of the plugin API: `NativePlugin.historyReader(for:)` returns a
`SessionHistoryReader` (`sources()` lists files without parsing; `read(_:resuming:)` turns one
into a `HistorySession` of documents, or only its new part when resumed from an offset). Built in:

- **Claude Code** (`ClaudeCodeHistoryReader`, `~/.claude/projects/<folder>/<session id>.jsonl`, or
  `$CLAUDE_CONFIG_DIR`). Reads `user` records (a string prompt, `text` blocks, `tool_result`
  blocks joined to their call by `tool_use_id`), `assistant` records (one `text`, `thinking` or
  `tool_use` block each), and `ai-title`, `custom-title` (wins) or `summary` for the title. Skips
  `isMeta`, `isSidechain`, harness-injected context (`<command-name>`, caveats) and the large
  `api-request*`, `attachment` and `file-history-*` records before parsing them. `TodoWrite` is the
  plan. Subagent logs (`<session>/subagents/`) aren't read.
- **Codex** (`CodexHistoryReader`, `~/.codex/sessions/YYYY/MM/DD/rollout-*.jsonl`, or
  `$CODEX_HOME`). `session_meta` gives the thread id, cwd and start; `response_item` gives
  `message` (user and assistant; `developer` messages and `<environment_context>`/AGENTS.md
  injections skipped), `reasoning` summaries, `function_call`/`custom_tool_call` with their
  `*_output` by `call_id`, and `update_plan`. Names come from `~/.codex/session_index.jsonl`
  (`thread_name`, last line wins), else the first prompt. `event_msg` records duplicate the
  conversation and are skipped. Archived threads (`archived_sessions/*.jsonl.zst`) are
  zstd-compressed, which Foundation can't read, so they aren't indexed yet.

Both formats were checked against real files (Claude Code 2.x, Codex CLI rollouts from 2026) by
their record shapes only; the test fixtures are synthetic files with those shapes. The session ids
are the ones ACP uses (`session/list` and `session/load` take them as they are), and tool call ids
are the agents' own (`toolu_…`, `call_…`), which the ACP adapters pass through as `toolCallId`.

Readers only read, and a pass reads only what's new. Each file has a **checkpoint**: its size and
modification time when it was read, and the byte offset just past the last complete line indexed.
A file whose size and time match is skipped without being opened. One that only grew is read from
its offset, and the new documents are appended to its session (a line still being written is left
for next time). Anything else (a file that shrank, or whose session a retention policy dropped) is
read from the start. Files of excluded projects are known by their checkpoint's folder and never
opened. Files are streamed a megabyte at a time, lines over 4 MB (an image pasted into a tool
result) are skipped, and each line's JSON is parsed in its own autorelease pool, so memory stays
flat whatever the file's size. Batches are capped at 25 sessions, 2,000 documents or 4 MB of text,
and each commits with its files' checkpoints, so a pass that's cancelled, crashes or quits
continues where it stopped. Files never indexed go first, newest first.

Priority: the first fill runs at utility priority so search is useful soon; once a pass has
finished (`meta.filled`), later passes run at background priority. Either **pauses on battery or
in Low Power Mode**, continuing when the power source changes (IOKit's notification, no polling).
Nothing runs before the window is up: the index opens two seconds after launch, off the main
thread, and Native's own lists are consulted only for the sessions a pass actually reads.
Turns of agents with a reader don't re-index the live transcript: a pass a few seconds after the
turn reads just the lines it added to the agent's log, so each session has one source.
What Native already knows wins over the history: the sidebar's title, the project a session is
listed in, and whether it's archived.

## Opening a result

A hit carries an **anchor**: a tool call's id, an inter-session message's id, or for a message the
first 80 characters of its text (message ids are minted fresh on every replay, so they can't be
stored). Opening selects the task (listing it under its project first if the sidebar doesn't have
it yet, adding the project if Native doesn't), waits for it to load, finds the item by its anchor
(falling back to the first item containing a query word), and sets
`SessionModel.transcriptReveal`. The standard transcript unfolds the item's turn, scrolls it to the
center and tints it for a moment.

## Privacy

Local only: the index is a file in the app's own Application Support folder, queries never leave
the process, and nothing is sent anywhere. Settings ▸ Search turns reading the agents' history off,
excludes projects (their tasks are removed and never indexed), and clears the index. Turning
the Search plugin off stops indexing altogether.

## Clients and the host

The index belongs on the host (docs/durability.md), next to the agents' files, so the iPad and
iPhone search the Mac's history. The package already builds for iOS and every type it returns is
`Codable`. Proposed `_native/search/*` methods, for the host protocol:

| Method | Does |
| --- | --- |
| `_native/search/query {query: SearchQuery}` → `SearchResults` | `SearchQuery` is `{text, filters, limit, hitsPerSession}`; results are groups of `{session, hits, hitCount}`, hits carry `{id, role, anchor, date, hasDiff, snippet: {runs: [{text, isMatch}]}}` |
| `_native/search/status` → `{indexing: {phase, done, total}, statistics: {sessions, items, bytes}}` | for the panel's progress line and Settings |
| `_native/search/changed` (notification) | the index moved on (a batch landed, a turn was indexed), so an open panel searches again |
| `_native/search/configure {includesAgentHistory, excludedFolders}` | Settings ▸ Search, needing the owner grant like `_native/plugins/set_enabled` |
| `_native/search/clear` | forget everything and refill |

A client resolves a hit's anchor against the transcript it attached to, as the Mac does now.

## Performance

Measured with `SEARCH_BENCH=1 swift test -c release --filter benchmark` in `Packages/Search`:
3,000 sessions, 183,000 items of 40 words each, 4,000-word vocabulary.

| Query | Time |
| --- | --- |
| one common word (`timeout`) | 13 ms |
| two words | 11 ms |
| identifier part (`store`, matching `SessionStore`) | 12–14 ms |
| prefix (`dep`) | 12–18 ms |
| phrase | < 1 ms |
| word plus `agent:` filter | 14 ms |

On real history (this Mac's, read-only into a throwaway index with
`SEARCH_REAL_HISTORY=1 swift test -c release --filter RealHistoryCheck`, which prints counts and
timings only): Claude Code 379 files, 870 MB, read in 6 s (235 conversations; the other 144 files
hold only slash commands); Codex 112 rollouts, 581 MB, read in 3 s. 344 sessions became 26,700
documents in a 55 MB index. A known phrase, a file path and a command each found their task in
1–3 ms; an identifier part (`catalog`) 18 ms, `agent:codex test` 29 ms, all measured while the Mac
was under a load average near 300. The pathological query, a lone stopword matching nearly every
document (`the`), took 91 ms under that load; it's the one case past the 50 ms budget, and typing
a second word brings it back under.

In the app (Debug build, `scripts/perf/measure.sh --name perf-search`, real history of 533
files and 1.5 GB):

| Measurement | Before checkpoints | After |
| --- | --- | --- |
| Main-thread CPU to first frame, history search on | 585–716 ms (332–352 with it off) | 333–374 ms, the same as with it off |
| A launch with nothing new: CPU over its first 25 s | 15–45% for minutes, the whole history parsed again | 0.81–0.89 s, against 0.78–0.83 s with history search off |
| Footprint after a launch with nothing new | up to 370 MB while parsing | 88–93 MB (89–100 MB with it off); 114 MB idle with the window up |
| The first fill | not measured | 15 s of CPU over 35 s at utility priority, then idle |

Indexing is the heavy part: off the main thread, in batches, at background priority once the
first fill is done, and stopped on battery. Most lines are skipped by a byte search before any
JSON is parsed, which is why 1.4 GB reads in under ten seconds the first time, and checkpoints mean
later launches read only what was added since.

## Not yet

- Subagents' own transcripts as hits of their parent task.
- Codex's archived threads (zstd).
- Agents searching the index themselves, through an orchestration MCP tool.
- The host-side index and the protocol above.
