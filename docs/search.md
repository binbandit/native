# Search

Find any task by what was said in it: plain text across every agent run, every agent and every
project, archived tasks included as a filter. ⇧⌘F (Go ▸ Search Tasks…) or **Search** at the top of
the sidebar opens it; Return opens the task scrolled to the exact message, highlighted.

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
it's being typed (`rollb` finds `rollback`). Symbols are part of the text: `AppModel.swift`,
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
          · source_path · source_stamp            -- the history file it came from, and its size+mtime
items     session_row → sessions (cascade) · ordinal · role · date · has_diff · anchor · body · parts
items_fts fts5(body, parts, content='items', tokenize='unicode61 remove_diacritics 2'), kept by triggers
```

- **Code-aware tokens.** `unicode61` already splits on everything that isn't a letter or digit, so
  `snake_case`, `kebab-case`, `a/b/c.swift` and `--flag` come apart into words. camelCase it can't
  split, so each item also stores its identifiers' pieces in `parts` (`SessionStore` →
  `session store`, `parseHTTPHeader` → `parse http header`). `body` keeps the text intact for
  phrases and snippets; queries match both.
- **Ranking.** `bm25(body 1.0, parts 0.4)`, times a recency boost (1.5× today, 1.25× at two weeks,
  fading to 1× over months), times a role weight (title 1.5, prompt 1.25, reply and plan 1.0, tool
  0.8, reasoning 0.6). The best 600 hits are grouped by task, tasks ordered by their best hit, each
  showing its best three.
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
| Live sessions | 2 s after a turn ends or fails (coalesced, so a draining queue is one write) | the whole transcript from `SessionState`, converted off the main thread; never per streamed chunk |
| Agents' own history | at launch, when enabled, and when the panel opens if the last pass was over 5 minutes ago | through each agent plugin's `SessionHistoryReader`; newest files first |
| Agents without a reader | when the user opens one of their sessions and it has loaded | the loaded transcript, as for live sessions |

**History readers** are part of the plugin API: `NativePlugin.historyReader(for:)` returns a
`SessionHistoryReader` (`sources()` lists files without parsing, `read(_:)` turns one into a
`HistorySession` of documents). Built in:

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

Readers only read: memory-mapped, line by line, a cheap byte search deciding which lines are worth
parsing. A pass is **resumable**: each batch (25 sessions or 2,000 documents) commits with its
files' stamps, so a pass that's cancelled, crashes or quits continues where it stopped, and an
unchanged file is never read twice. It runs at background priority, and **pauses on battery or in
Low Power Mode**, continuing when the power source changes (IOKit's notification, no polling).
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
excludes projects (their sessions are removed and never indexed), and clears the index. Turning
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

Queries stay well under the 50 ms budget. Indexing is the heavy part and runs at background
priority in batches; see the real-history numbers in the PR that landed this.

## Not yet

- Subagents' own transcripts as hits of their parent task.
- Codex's archived threads (zstd).
- Agents searching the index themselves (an orchestration MCP tool, as Orca offers).
- The host-side index and the protocol above.
