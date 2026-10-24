# Command knowledge

Fine print describes commands using local, reviewed data, without a model, subprocess, filesystem
inspection, DNS lookup, or network request. It preserves the original command and character ranges.
`Packages/ApprovalAnalysis/Sources/ApprovalAnalysis/Resources/commands.json` ships as a Swift package
resource on Mac and iPad. Add a tool there and add real command lines to
`Packages/ApprovalAnalysis/Tests/ApprovalAnalysisTests/CommandCoverageExamples.swift`.

These are descriptions of conventional tool syntax, not proof of an executable's identity or of a
successful result. An executable on PATH, alias, configuration, hook, script, server, or file may
behave differently. Native does not claim to have inspected any of them. Unknown programs,
subcommands, flags, missing option values, or unsupported shell syntax produce no annotations or
alternative. They retain the existing unknown-command approval behavior.

## Version 1 schema

The root object has exactly three fields. Unknown fields are rejected to catch misspellings.

```json
{
  "version": 1,
  "programs": [
    {
      "executables": ["acme-check"],
      "commands": [
        {
          "words": ["inspect"],
          "summary": "inspect {count} items",
          "consequence": "Configuration and item contents have not been inspected.",
          "destructive": false,
          "options": [
            {"names": ["--verbose", "-v"], "summary": "show more detail", "destructive": false, "value": "none"}
          ],
          "operands": {"minimum": 1, "maximum": 8, "summary": "item: {value}", "paths": false}
        }
      ]
    }
  ],
  "locations": []
}
```

| Field | Meaning |
| --- | --- |
| `version` | Integer `1`. Other versions reject the document. |
| `programs` | Up to 256 programs. Each entry validates independently; a bad entry does not discard its neighbours. |
| `executables` | 1 to 16 unique, case-sensitive literal names or paths, up to 256 characters each. No basename guessing: `/tmp/git` is not `git`. |
| `commands` | 1 to 128 command grammars. |
| `words` | Exact subcommand words (0 to 4), immediately after the executable. The longest matching sequence wins. Empty means the program itself. |
| `summary` | Short action text, up to 300 characters. Optional `{count}` is the parsed operand count. |
| `consequence` | Short plain text, up to 300 characters. No template variables. Describe effects and what was not inspected, without promising success, safety or undo. |
| `destructive` | Required Boolean. True uses deliberate confirmation. An option can raise this to true, never lower it. Build tools and script runners use true because their inputs execute code. |
| `options` | Up to 128 known options. An unknown option rejects the whole command. Names must be unique within a command. |
| `optionsBeforeOperands` | Optional Boolean, default false. True ends option parsing at the first operand, for wrappers such as `sudo` and `ssh`. Remaining arguments are explicitly uninspected. |
| `allowsTerminator` | Optional Boolean, default true. False rejects a standalone `--`; used for `find`, whose expression predicates must never become unexamined operands. |
| `shortClusters` | Optional Boolean, default false. Enables combinations such as `rm -rf` and `tar -xzf`. Every flag must be known; a value-taking flag consumes the rest or the next word. |
| `operands.minimum`, `maximum` | Required nonnegative minimum and optional maximum, each up to 128. Omit maximum (or use null) for no grammar-specific upper bound. The parser still caps the entire command at 512 tokens. |
| `operands.summary` | Up to 300 characters. `{value}` is the literal unquoted argument. `{scope}` is lexical reach and `{location}` is a conventional location name when `paths` is true. User text is substituted last. |
| `operands.paths` | Required Boolean. True permits lexical normalization against the requested working directory and task worktree. It never resolves symlinks or reads contents. |

An option has `names`, `summary`, `destructive`, and `value`. Its names start with `-` (the reserved
`--` terminates options). `value` is `none`, `next` (a separate next word), or `attached` (a separate
word, `--name=value`, or `-nvalue`). Values beginning with `-` must use an attached form; otherwise
the grammar is ambiguous and falls back. `next` accepts an explicitly quoted empty word, as BSD
`sed -i ''` requires. GNU `sed -i` without a suffix is intentionally unsupported; `--in-place` is
listed separately. There is no platform guessing.

Options may also include `replacement` and `alternative`. Both are required together; replacement
must be the exact name of a valueless option in the same command that has no replacement of its
own. Only whole valueless option tokens can be replaced. Short clusters containing replacements
are rejected. Every matching occurrence is replaced, preserving all other characters, quoting, and
whitespace. The alternative is a suggestion the person can send as a new instruction, never a
command executed by Native. The shipped `git push --force` alternative is `--force-with-lease`;
both remain destructive because a lease may still replace remote history. Optional command fields
`noSuggestionWithOptions` (known option names) and `noSuggestionWithOperandPrefixes` (nonempty
literal prefixes, up to 64 characters) suppress alternatives in incompatible forms. The shipped
push rule blocks them with `--mirror`, `--delete`, or operands starting with `+` or `:`. These forms
may force updates or delete refs independently of a standalone force flag.

A location has `kind`, `path`, and `summary` (up to 300 characters, no templates). `kind` is
`homePrefix` for a home-relative path or `component` for a single exact path component. Both use
component boundaries after lexical normalization, so `.build/../source` is not a build cache.
`~/` only expands when the shell token was unquoted and the task's home directory is known. A remote
task does not borrow the client's home. The shipped entries identify DerivedData, node_modules,
and .build as conventional locations. They never lower deletion risk or claim files are rebuildable:
local edits, replaced directories and symbolic links have not been measured.

The document is limited to 1 MiB and 64 locations. Identifiers use ASCII letters, digits, `.`, `_`,
`+`, and `-`, with `/` additionally allowed between executable path components. Text cannot contain
control characters or unknown template placeholders. Duplicate command sequences, option names,
executables, invalid bounds, and invalid alternatives reject the containing program with a numbered
field diagnostic. Broken JSON or the wrong root shape rejects the document. The bundled document
must have zero diagnostics in tests.

## Organization extensions

A manifest plugin embeds the same object under `commandKnowledge`:

```json
{
  "id": "acme.commands",
  "name": "Acme command explanations",
  "commandKnowledge": {
    "version": 1,
    "programs": [],
    "locations": []
  }
}
```

Replace the empty programs array with entries like the example above. These are trusted, reviewed
statements supplied by the plugin author, not text generated from the command. Schema validation
cannot prove that an organization's description of its internal tool is accurate. Review that data
as carefully as the tool. Plugins add only data, with no new code execution or downloads.

An administrator can deliver the identical JSON as a string in the managed preference
`policy.approvals.knowledge`. The policy package validates it with the same loader and reports
ignored entries through its usual diagnostics. No URL or path indirection is supported. Built-in
knowledge wins, followed by organization policy, then enabled plugins in registry order. Any program
whose executable overlaps an earlier source is rejected as a whole. Extensions cannot replace a
shipped command or lower its risk. Locations are additive and cannot change risk.

A disabled plugin, or one excluded by `policy.plugins.allowed`, contributes nothing. Reloading the
plugin, switching it, or changing managed policy invalidates the registry's cached knowledge. All
load and collision messages appear in Command Diagnostics while Fine print is on. Approvals keep
working if any contribution is damaged. This follows lean core's existing plugin and policy seams;
it does not introduce another extension system.

## Local coverage counts

With Fine print on, Native counts bare, unknown program names when live approval requests reach the
client model, including requests in tasks whose view is not open. Counts are stored only at:

```text
Application Support/<app bundle id>/CommandKnowledge/unknown-programs.json
```

Isolated instances use their own bundle id. The JSON contains only `program` and `count`. No command
arguments, executable paths, environment, task ids, timestamps, or transcripts are stored. Only
ASCII bare names up to 64 characters qualify. A recognized program with an unsupported flag or
subcommand is not an unknown program. Compound shell syntax and paths are omitted rather than
heuristically extracting a name. This is an observation count, not an audit of all commands an agent
runs: commands that never ask Native for approval and history replays are not counted.

Counting is on only while Fine print is on, the user permits it, and policy permits it. Set
`policy.approvals.countUnknownPrograms` to false to disable collection, regardless of the user choice.
True permits the user choice; it does not force collection. Turning collection off does not read or
write the file for incoming requests. Existing counts remain purgeable. No network capability,
telemetry event, exporter, background upload, or host synchronization reads this file. Names never
leave this client through this feature, even when organization telemetry is configured.

Help > Command Diagnostics opens Settings > Privacy. It shows the top ten names by descending count,
with alphabetical ties, plus knowledge-load and storage errors. The same page and Help menu let the
user disable counting or clear the file, including when policy has disabled counting. The list is
bounded at 256 names, each count at 1,000,000. At most 4,096 request identities are deduplicated in
memory per app launch; counting stops when that limit is reached. Identities are never written.
Repeated updates to one request count once while its session is loaded; reloading a session or
launching the app again can observe a pending request again.
Clear deletes the file and invalidates queued observations, but keeps in-memory deduplication so a
still-open request cannot immediately repopulate it. New requests can count again if enabled.

All new UI and counting remain behind the existing default-off Fine print gate. This build has no
visual verification on elara. Check the approval diagram and Privacy diagnostics on the main Mac
in light/dark and at narrow widths before enabling the feature by default.

## Checks

```sh
nice -n 10 swift test --package-path Packages/ApprovalAnalysis -j 4 --filter 'ApprovalAnalysisTests|CommandKnowledgeTests|UnknownCommandCountsTests'
nice -n 10 swift test --package-path Packages/NativePolicy -j 4 --filter 'NativePolicyTests|CatalogPolicyTests|CommandKnowledgePolicyTests|SampleProfileTests'
```

Coverage examples exercise every shipped command grammar, source-range preservation, expected
confirmation level, malformed entries, source collisions, unsupported syntax, known-location
boundaries, local persistence, limits, disabled collection, and purge. Unknown cases must have no
parts and no suggested command. Adding a program does not require editing the matching engine.
