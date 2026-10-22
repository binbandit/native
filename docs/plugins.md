# Build a Native plugin

How to extend Native with a plugin: add a coding agent that speaks ACP, give every agent session
an extra MCP server, or add a multi-agent workflow, by writing a `plugin.json` into Native's
plugins folder, and how to check that Native loads it.

This file is the canonical description of Native's plugin format. Native serves it to agents as
the `build-a-native-plugin` skill (the `get_skill` tool of its `native` MCP server), so it's
written for an agent doing the work as much as for a person.

## What a plugin is

Everything Native runs with comes from plugins, its own agents included. There are two kinds:

- **Manifest plugins** are a `plugin.json` file and nothing else. They contribute data: agents,
  MCP servers and workflows. Anyone can write one, without rebuilding Native. This is what you
  write to extend Native for a user.
- **Built-in plugins** are Swift types compiled into Native (`native/Plugins/`). They can also
  run code: title sessions, react to session events, and give each session its own MCP server.
  See [Built-in plugins](#built-in-plugins) for that part of the API.

## Where plugins live

Each manifest plugin is a folder holding a `plugin.json`:

```
~/.native/plugins/
  my-plugin/
    plugin.json
```

Name the folder after the plugin's `id`. Native reads the folder at launch, and again when the user
clicks **Reload** in Settings ▸ Extensions. Folders are read in alphabetical order, after the
built-in plugins, so a plugin can't take over a built-in plugin's id. The user can turn any plugin
off in Settings ▸ Extensions. Changes apply to tasks started afterwards; agents start or stop right
away.

A plugin that fails to load is skipped and listed in Settings ▸ Extensions with the reason, such as
"Missing \"name\"." Other plugins still load.

## plugin.json

```json
{
  "id": "my-plugin",
  "name": "My Plugin",
  "version": "1.0.0",
  "description": "One sentence the user sees in Settings.",
  "agents": [],
  "mcpServers": [],
  "workflows": []
}
```

| Field | Required | Meaning |
| --- | --- | --- |
| `id` | yes | Unique across all plugins. Lowercase words joined with hyphens. Also the folder name. |
| `name` | yes | What the user sees. |
| `version` | no | Free-form, for the user. |
| `description` | no | One sentence: what the plugin adds. |
| `agents` | no | Coding agents, see [Agents](#agents). |
| `mcpServers` | no | MCP servers for every session, see [MCP servers](#mcp-servers). |
| `workflows` | no | Multi-agent workflows, see [Workflows](#workflows). |
| `themes` | no | Code themes and accent palettes, see [Themes](#themes). |
| `iconSets` | no | App icon families, see [Icon sets](#icon-sets). |
| `celebrations` | no | Dated celebrations that dress the icon and Home, see [Celebrations](#celebrations). |
| `experiments` | no | Gates and parameters in Settings ▸ Labs, see [Experiments](#experiments). |

Unknown fields are ignored. Nothing in `plugin.json` is secret: don't put API keys in it.

## Agents

An agent is a command that speaks the [Agent Client Protocol](https://agentclientprotocol.com) over
stdio. Native launches it once, through the user's login shell environment, and runs every session
of that agent through it.

```json
{
  "id": "gemini",
  "name": "Gemini",
  "symbol": "sparkles",
  "command": "gemini",
  "args": ["--experimental-acp"],
  "env": { "GEMINI_TELEMETRY": "off" },
  "resolveExecutables": {},
  "mcpConfig": null
}
```

| Field | Required | Meaning |
| --- | --- | --- |
| `id` | yes | Unique across every plugin's agents. Keep it stable: Native remembers sessions and their titles by it. |
| `name` | yes | What the user sees. |
| `symbol` | no | An SF Symbol name, shown where there's only room for an icon. |
| `command` | yes | The executable, looked up on the user's login shell `PATH`. |
| `args` | no | Arguments. |
| `env` | no | Extra environment variables. |
| `resolveExecutables` | no | Variables to set to the absolute path of a command on `PATH`, such as `{"CLAUDE_CODE_EXECUTABLE": "claude"}`, so an adapter runs the user's own CLI. |
| `mcpConfig` | no | Where the agent keeps its own MCP configuration (`"claude-code"`, `"codex"` or `"cursor"`), so Native can show the servers it already loads. |
| `icon` | no | The agent's icon: `{"path": "icon.svg"}` (or just `"icon.svg"`), an image in the plugin's folder; `"apps"`, bundle identifiers of apps whose icon to use when installed; `"registry"`, the agent's id in the [ACP registry](https://agentclientprotocol.com/get-started/registry), whose icon Native fetches. A monochrome SVG is drawn in the text color. Without one, Native shows a monogram. |
| `requires` | no | Commands besides `command` that must be on `PATH` for the agent to count as installed, such as the CLI an adapter drives: `["claude"]`. Native doesn't start an agent that's missing one; it offers it in Add Agent. |
| `setup` | no | How to get the agent going, shown in Add Agent and never run: `install` (a command to paste in a terminal), `docs` (a URL) and `signIn` (a terminal command that signs in). |
| `idleSessionTimeout` | no | Seconds one of the user's sessions may sit unused (not shown, not working, no draft) before Native closes it, here and in the agent (`session/close`), loading it back when it's selected again. Set it only for an agent that pays for every open session, such as a process each, and reopens one faithfully: transcript, model and mode. Without it, sessions stay open. |
| `idleUnloadTimeout` | no | Seconds a session may sit with nothing happening (no turn, approval, question or queued message) before Native's host unloads it from the agent (`session/close`). The session stays where it is, transcript included, and resumes without a replay (`session/resume`) the next time it's used; once none of the agent's sessions is loaded and nothing used the agent for as long, its process ends too, and it starts again when needed. The `idleUnloadTimeout` user default overrides it for every agent. For an agent that holds a lot per loaded session, or keeps things after closing one, and can resume (it advertises `close` and `resume`); others ignore it. Without it, sessions stay loaded. |
| `renameCommand` | no | A command that names a session in the agent without asking a model, such as Codex's `"/rename"`. Native sends it, hidden, ahead of a turn whenever the agent's name for the session isn't Native's: before a new session's first message with that message's first words (so an agent that titles new sessions with a model of its own doesn't), and before the next message once Native's title or the user's rename exists, so the agent's own session list shows the same names (when the host keeps titles, `HostTitles`). If the agent ever answers it with a model's turn, Native stops sending it to that agent. Stopping during naming cancels the pending user turn too; a reply from a replaced connection cannot send or finish that turn. |
| `authMethods` | no | Ways to sign the agent in that it accepts without advertising them over ACP, in ACP's own shape, for hosts nobody sits at: a key in a variable it reads (`{"id": "anthropic-api-key", "name": "Anthropic API key", "type": "env_var", "vars": [{"name": "ANTHROPIC_API_KEY"}], "link": "https://…"}`), or a page-and-code sign-in it offers only to clients that open links (`"type": "_native/link"`). The host sets only variables declared here or by the agent. See docs/agents.md, "Signing in on a host with no screen". |

Agents that don't speak ACP themselves need an adapter, usually run with `npx`. Pin its version so
upgrades are deliberate:

```json
{ "command": "npx", "args": ["--yes", "@agentclientprotocol/claude-agent-acp@0.93.0"] }
```

## MCP servers

Every MCP server a plugin lists is handed to every agent session when it starts or is reopened,
whichever agent it runs on. Give exactly one of `command` (a local server the agent launches over
stdio) or `url` (a server already running, over HTTP).

```json
{ "name": "docs", "command": "npx", "args": ["--yes", "@example/docs-mcp@2.1.0"], "env": { "DOCS_ROOT": "/Users/me/docs" } }
```

```json
{ "name": "tracker", "url": "http://127.0.0.1:7341/mcp", "headers": { "X-Team": "mobile" } }
```

| Field | Meaning |
| --- | --- |
| `name` | The server's name. Agents show its tools under it, such as `mcp__docs__search` in Claude Code. |
| `command`, `args`, `env` | A stdio server: the agent runs `command` with `args` and `env`. |
| `url`, `headers` | An HTTP server (MCP Streamable HTTP), with extra request headers. |

The agent starts stdio servers itself, so `command` must work for the agent: prefer `npx` or an
absolute path. Claude Code and Codex both accept HTTP servers. Pick a `name` other servers don't
use; `native` is Native's own.

## Workflows

A workflow is a reusable sequence of agent tasks the user starts from Native, such as "plan with
one agent, implement with another, review with the first". A broken workflow is listed with its
problems instead of failing the whole plugin.

```json
{
  "id": "explain-then-test",
  "name": "Explain, then test",
  "summary": "One agent explains the code, a different one writes tests from the explanation.",
  "symbol": "text.magnifyingglass",
  "input": { "label": "Which code?", "placeholder": "The retry logic in Uploader.swift", "required": true },
  "steps": [
    { "id": "explain", "title": "Explain", "prompt": "Explain {{input}} in {{project}}. Don't edit files." },
    {
      "id": "test", "title": "Write tests", "agent": { "differentFrom": "explain" },
      "approval": "Check the explanation before tests are written.",
      "prompt": "Write tests for {{input}} in {{cwd}}, based on this explanation:\n\n{{steps.explain.output}}"
    }
  ]
}
```

Workflow fields: `id` and `name` (required), `summary` (one sentence for the picker), `symbol` (an
SF Symbol), `input` (what the user is asked before it runs: `label`, `placeholder`, `required`)
and `steps`.

Step fields:

| Field | Meaning |
| --- | --- |
| `id` | Required. Other steps refer to the step by it. |
| `title` | What the user sees. Defaults to the id. |
| `kind` | `"agent"` (the default) runs `prompt` as an agent task, `"pullRequest"` opens a pull request from `pullRequest`, `"script"` runs `script` in Native's script runtime with the rendered `prompt` as its input. |
| `agent` | Which agent runs it: an agent id such as `"codex"`, `{"sameAs": "<step>"}`, or `{"differentFrom": "<step>"}`. Omitted means the run's default agent. Prefer the relative forms: they work with whatever agents the user has. |
| `continues` | A step id: run in that step's task, so the agent keeps its context. |
| `prompt` | The task, with `{{variables}}`. |
| `after` | Step ids that must finish first. Omitted means the step before; `[]` starts right away, in parallel. |
| `approval` | `true`, or a message saying what to check: the run waits for the user, who can edit the prompt. |
| `goal` | `true`, or `{"maxIterations": 8, "maxDuration": 1800, "maxCost": 5}`: keep working until the goal is met, within the budget. |
| `pullRequest` | `{"title": "{{title}}", "body": "...", "draft": false}`, for a `pullRequest` step. |
| `script` | The source a `script` step runs. |

Template variables: `{{input}}`, `{{title}}`, `{{cwd}}`, `{{project}}`,
`{{steps.<id>.output}}` (a finished step's result) and `{{steps.<id>.agent}}` (the agent it ran
on).

## Themes

A plugin can add code themes and accent palettes. They are data only: nothing runs. Each one is
checked when the plugin loads, and one that fails is left out with its reason on the plugin's row
in Settings ▸ Extensions; the plugin and its other themes still work. Themes appear in Settings ▸
Appearance beside the built-in ones, named with the plugin (“Midnight (Acme Themes)”). Turning the
plugin off takes them away at once, and a window using one goes back to the default.

```json
"themes": {
  "code": [
    {"id": "midnight", "name": "Midnight", "dark": {"foreground": "#E6E6E6", "background": "#101318", "comment": "#7A8494", "...": "..."}}
  ],
  "accents": [
    {"id": "sea", "name": "Sea",
     "light": {"accent": "#2C5BA9", "hover": "#244B8C", "pressed": "#1B3A6E", "text": "#2C5BA9", "onAccent": "#FFFFFF", "subtle": "#ECF0F7"},
     "dark": {"accent": "#9DBCF0", "hover": "#AEC8F3", "pressed": "#7F9CCB", "text": "#9DBCF0", "onAccent": "#0D1A30", "subtle": "#222A38"}}
  ]
}
```

| Field | Meaning |
| --- | --- |
| `code[].id`, `name` | The theme's id (no slashes; unique within the plugin) and what the user sees. |
| `code[].light`, `dark` | One or both palettes, each with every role as `#RRGGBB` or `#RRGGBBAA`: `foreground`, `background`, `comment`, `keyword`, `string`, `constant`, `function`, `variable`, `tag`, `type`, `operator`, `regex`, `invalid`, `punctuation`, `insertedForeground`, `insertedBackground`, `deletedForeground`, `deletedBackground`, `changedForeground`, `changedBackground`, `selection`, `lineHighlight`. `foreground` must reach 4.5:1 on `background`, the syntax colors 2:1 (no fainter than the faintest built-in theme). The terminal takes its ANSI colors from these roles. An optional `strong` list names roles set a heavier weight, as Native's dark keywords are: `"strong": ["keyword"]`. |
| `accents[].id`, `name` | As for code themes. Accents appear under Settings ▸ Appearance ▸ Accent, beside “Match app icon”. |
| `accents[].light`, `dark` | Both, each with `accent`, `hover`, `pressed`, `text`, `onAccent` and `subtle` as opaque `#RRGGBB`. `onAccent` must reach 4.5:1 on `accent`, and `text` 4.5:1 on Native's background in each tone (Paper and Wool in light mode, Standard and True Black in dark). |

Tone sets like Paper and Wool, or Standard and True Black, aren't open to plugins yet (see `docs/decisions.md`).

## Icon sets

An icon set is a family of app icons: one for each build channel (`stable`, `beta`, `nightly`,
`dev`), each in light and dark, plus how Home's emblem dresses up with it. A set that no celebration
uses is offered in Settings ▸ Appearance beside the built-in icons, credited to the plugin. A
celebration uses one by its id (any enabled plugin's).

```json
"iconSets": [
  {
    "id": "acme.sunset",
    "name": "Sunset",
    "icons": {
      "stable":  {"light": "icons/stable-light.png",  "dark": "icons/stable-dark.png"},
      "beta":    {"light": "icons/beta-light.png",    "dark": "icons/beta-dark.png"},
      "nightly": {"light": "icons/nightly-light.png", "dark": "icons/nightly-dark.png"},
      "dev":     {"light": "icons/dev-light.png",     "dark": "icons/dev-dark.png"}
    },
    "palette": {"light": ["#C2471B", "#3B2A4F"], "dark": ["#FF9A62", "#C9B6F2"]}
  }
]
```

| Field | Meaning |
| --- | --- |
| `id` | Namespaced with the plugin's id: `<plugin-id>.<name>`, lowercase. Keep it stable; the user's choice is stored by it. |
| `name` | What the user sees. A string, or translations by language: `{"en": "Sunset", "es": "Atardecer"}`. |
| `icons` | Images by channel, as paths inside the plugin's folder (1024×1024 PNG). The set applies only when all four channels have both images; otherwise it's listed with what's missing. `"forthcoming"` lists it without icons. |
| `home` | `{"mark": "<id>"}`: one of Native's Home editions (`native.halloween`, `native.dia-de-muertos`). |
| `caption` | One line shown where the set is picked as a celebration's style, such as "A calavera instead of Native's interlock." |
| `palette` | Colors per appearance, most prominent first. With two or more, Home draws the emblem's links in the first two when there's no `home` mark, or the mark isn't in this version. |

Each set is checked on its own when the plugin loads: one with an id outside the plugin's namespace,
a duplicate id, or an image path that leaves the plugin's folder (`..`, an absolute path, a symlink
out) is left out and listed under Settings ▸ Celebrations ▸ Couldn't load; the rest still load.

Platforms differ. On the Mac, Native applies the images at runtime through the Dock; runtime images
are flat, so they don't get the system's Clear and Tinted icon looks, which only Original has. On
iPad and iPhone, iOS only switches between icons compiled into the app, so a plugin's set can't
become the home-screen icon there: the picker marks it "Mac only", and it still restyles Home.

## Celebrations

A celebration dresses Native's icon and Home on its dates, from an icon set. Settings ▸ Celebrations
lists every celebration all year; each is off until the user turns it on, and installing a plugin
never turns one on. When two overlap, a celebration on its own dates wins over another's longer
decorative window, then the user's order decides, so two editions are never blended.

```json
"celebrations": [
  {
    "id": "acme.lantern-night",
    "title": {"en": "Lantern Night", "es": "Noche de Faroles"},
    "aliases": ["Lantern Festival night"],
    "description": "Paper lanterns glowing through the links.",
    "tags": ["cultural"],
    "provenance": {"sources": ["https://example.org/calendar"], "publisher": "Example Council", "reviewed": "2026-10-18"},
    "calendar": {"kind": "fixed", "start": "12-30", "end": "01-02", "tradition": "Example City"},
    "display": {
      "windows": [{"id": "extended", "title": "Extended, decorative", "daysBefore": 5, "daysAfter": 2}],
      "defaultWindow": "core"
    },
    "iconSet": "acme.lanterns"
  }
]
```

| Field | Meaning |
| --- | --- |
| `id` | Namespaced with the plugin's id, lowercase, and stable forever: the user's choices are stored by it. A regional variant gets its own id. |
| `title`, `aliases`, `description`, `tags` | What the user sees and searches. Search ignores accents and case and covers the title in every language, the aliases and the tags. Tags help browsing and never turn anything on. |
| `provenance` | Where the dates come from: `sources` (URLs), `publisher`, `authority`, `dataVersion`, `reviewed` (`yyyy-MM-dd`), and `coverage` (`{"from": 2026, "through": 2030}`) for annual tables. After `through`, nothing shows and the catalogue says the dates have ended. |
| `calendar` | `kind` and its rule; `tradition` names the calendar or region; `boundary` is `civil-day` (default), `sunset` or `nightfall`; `provisional` marks dates awaiting confirmation. |
| `display` | `windows`: decorative spans around the core dates, in calendar days (0 to 60 either side); `defaultWindow`: `core` (default) or one of their ids; `treatment`: `festive` (default) or `quiet` for solemn observances. |
| `iconSet` | The icon set it shows. Omitted lists it with its artwork forthcoming, changing nothing. |
| `alternateIconSets` | Other styles of the same celebration, by icon set id, which the user can pick instead. Give each set a `caption` saying how it differs. |
| `compatibility` | `manifestVersion` (1) and `minimumNativeVersion`; a newer one is listed as needing an update. |

Calendar kinds this version resolves:

| `kind` | Fields | Example |
| --- | --- | --- |
| `fixed` | `start`, optional `end` (`MM-dd`). An `end` before `start` crosses New Year; `02-29` occurs only in leap years. | `{"kind": "fixed", "start": "12-26", "end": "01-01"}` |
| `nth-weekday` | `month`, `weekday` (`"monday"`…), `ordinal` (1–5, or -1 for the last), optional `length` in days | US Thanksgiving: `{"kind": "nth-weekday", "month": 11, "weekday": "thursday", "ordinal": 4}` |
| `day-of-year` | `day`, optional `length` | Programmers' Day: `{"kind": "day-of-year", "day": 256}` |
| `western-easter`, `orthodox-pascha` | optional `offset` from Easter Sunday in days, `length` | Mardi Gras: `{"kind": "western-easter", "offset": -47}` |
| `table` | `occurrences`: `[{"start": "yyyy-MM-dd", "end": "yyyy-MM-dd"}]`, published annual dates | Lunisolar, Hebrew and Islamic dates from a named authority; cite it in `provenance` and mark moon-sighting dates `provisional`. After the last year, nothing shows and the catalogue says the dates have ended. |

Any other `kind` is accepted and listed as coming soon, never applied. Days are always local
calendar days, never multiples of 24 hours, so daylight saving and travel don't shift them.

Choices stay out of the manifest: which celebrations are on, which surfaces they change, the window,
the overlap order and skips are the user's, and updating a plugin never changes them. Turning a
plugin off puts the usual look back at once.

## Experiments

A plugin can try things out before they're finished, the way Native does: it declares experiments,
and the user turns them on in Settings ▸ Labs, where they're listed under the plugin's name with
their stage and what they change. Owner and review dates remain maintainer metadata.
Turning the plugin off removes its experiments and everything they change at once; the user's choices
are kept, so they come back with the plugin and survive
updates. Ids are namespaced by the plugin, so `fast-review` in the `acme` plugin is
`acme.fast-review` and never collides with Native's or another plugin's.

A `plugin.json` has no code to read an experiment, so its experiments act through the manifest:

- A **gate** (on or off) switches the plugin's own contributions. Mark an agent, MCP server,
  workflow, code theme, accent, icon set or celebration with `"experiment": "<gate-id>"`, and it's
  there only while the gate is on.
- A **parameter** (one of several values, a number from a range, or text) fills
  `${experiment:<parameter-id>}` placeholders in the plugin's agents' `args` and `env`, and its MCP
  servers' `args`, `env` and `headers`. Sessions started afterwards get the new value.

```json
{
  "id": "acme",
  "name": "Acme",
  "experiments": [
    {
      "id": "fast-review", "kind": "gate", "title": "Fast review",
      "summary": "Adds a one-step review workflow.", "stage": "labs", "reviewBy": "2027-01-31"
    },
    {
      "id": "verbosity", "kind": "parameter", "title": "Search verbosity",
      "summary": "How much detail the search server returns.", "stage": "beta", "reviewBy": "2027-01-31",
      "default": "normal",
      "options": [{ "value": "terse", "title": "Terse" }, { "value": "normal", "title": "Normal" }, { "value": "full", "title": "Full" }]
    }
  ],
  "mcpServers": [
    { "name": "acme-search", "command": "acme-search", "env": { "ACME_VERBOSITY": "${experiment:verbosity}" } }
  ],
  "workflows": [
    {
      "id": "fast-review", "experiment": "fast-review", "name": "Fast review",
      "summary": "One agent reviews the current changes.", "symbol": "checkmark.seal",
      "input": { "label": "What to focus on?", "required": false },
      "steps": [{ "id": "review", "title": "Review", "prompt": "Review the uncommitted changes in {{cwd}}. {{input}}" }]
    }
  ]
}
```

| Field | Required | Meaning |
| --- | --- | --- |
| `id` | yes | Lowercase words joined with hyphens, unique within the plugin. |
| `kind` | yes | `gate` or `parameter`. |
| `title`, `summary` | yes | What Labs shows: a name and one line on what changes. |
| `reviewBy` | yes | `YYYY-MM-DD`: when you'll make it a default, a setting, or delete it. Labs flags it after. |
| `stage` | no | `labs` (early, the default) or `beta` (nearly done). |
| `owner` | no | Who decides what happens to it. Defaults to the plugin's name. |
| `requiresRelaunch` | no | `true` when a change only applies the next time Native opens. |
| `default` | parameters | The value until the user picks one; a gate's is `true` or `false` (off if left out). |
| `options` | one of these, for parameters | `[{"value": "terse", "title": "Terse"}]`: values all text or all numbers. |
| `range` | | `{"min": 1, "max": 10, "step": 1}`: whole numbers, at most 200 of them. |
| `text` | | `{"placeholder": "…"}`: anything the user types. |

Each experiment is checked when the plugin loads. One that's malformed, has a value outside its
own options, or clashes with another experiment's id is listed under the plugin in Labs with its
problem, and the plugin and its other experiments still work. So is a contribution or placeholder
that names an experiment the plugin doesn't declare. A contribution behind a missing or broken gate
stays off, and a placeholder for a missing parameter is empty.

Plugins compiled into Native declare experiments in code instead (`NativePlugin.experiments`): gates
and parameters their code reads, and variants that replace an extension point's implementation
(see "Experiments" in `docs/architecture.md`). Their ids must start with the plugin's id.

## Built-in plugins

Behavior, rather than data, needs a built-in plugin: a Swift type in `native/Plugins/` (or a
feature's folder) conforming to `NativePlugin`, listed in `BuiltInPlugins.all`.

```swift
protocol NativePlugin: Sendable {
    var manifest: PluginManifest { get }
    /// Names sessions after what they're about.
    var titler: (any SessionTitler)? { get }
    /// MCP servers for one session, in addition to the manifest's.
    func mcpServers(for session: SessionContext) -> [MCPServer]
    /// Session lifecycle hooks, delivered to every enabled plugin in order.
    func handle(_ event: SessionEvent) async
}
```

A titler gets the user's own instructions for titles (Settings ▸ AI Instructions) in
`TitleRequest.instructions` and adds them after its own rules with `AIInstructionAddition.applied(to:)`,
so they change a title's style but never its format.

Every requirement but `manifest` has a default. `SessionContext` describes a session: Native's own
`clientID` (assigned before the agent creates the session, so per-session resources key by it),
the agent, the agent's `sessionID` once it exists, `cwd`, `title`, and `parentID` for subagents.
`SessionEvent` is one of `sessionStarted`, `promptSent`, `turnEnded`, `turnFailed`,
`permissionRequested` and `usageUpdated`. Native's notifications, sounds, session titles and
orchestration tools are built-in plugins written this way.

### Titles with the app closed

Tasks run in Native's host, which keeps working with every window closed: a laptop that started a
job and closed its lid, a Mac mini doing it. So the host titles tasks too, and a titler has to say
how it reaches the host:

```swift
protocol SessionTitler: Sendable {
    /// Nil when it can't write one right now (no model here, say).
    func title(for request: TitleRequest) async throws -> String?
    /// The host's own titler that writes the same titles; nil (the default) when it runs only in the app.
    var hostProvider: HostTitleProvider? { get }
}
```

The first enabled plugin with a titler decides, and the app tells each host it's connected to
(docs/durability.md, "Titles"):

- **A titler the host runs too** (`hostProvider: .onDevice`, Native's On-Device Titles, the same
  `OnDeviceTitleGenerator` in both): the host writes each task's title from its first message,
  whether or not an app is attached, with the user's title instructions, which the app hands it.
  Where the host has no model (Apple Intelligence off on that machine), it falls back to the next
  rule.
- **A titler that runs only in the app** (`hostProvider` nil): the host keeps each task's first
  message until an app with this titler is attached; that app writes the title and hands it to the
  host, which keeps it. So a task started with every app closed gets its title when one next
  connects. Meanwhile it goes by its agent's title, or else its first message, shortened.
- **No titler** (the plugin is off): tasks keep the titles their agents give them.

Either way the user's own title wins over all of them and lives in the host, so a rename on one
device shows on every other. A titler is asked once per task; one that fails isn't asked again.

## Testing a plugin

1. Check the file is valid JSON: `python3 -m json.tool ~/.native/plugins/my-plugin/plugin.json`.
2. Check every `command` runs from a login shell, the way Native starts it:
   `zsh -lc 'command -v gemini'`. For a stdio MCP server, run its command by hand; it should wait
   for input rather than exit.
3. Have the user click **Reload** in Settings ▸ Extensions (or restart Native), then check the plugin
   is listed and enabled, with no load failure under it.
4. Try what it adds: an agent appears in the agent picker and starts (its status shows on
   Home and in Settings ▸ Agents); an MCP server's tools show up in a new session; a workflow appears in the
   workflow picker; an icon set appears in Settings ▸ Appearance; a celebration appears in
   Settings ▸ Celebrations. To see a celebration without waiting for its date, launch Native with
   `-nativeDate yyyy-MM-dd`. Try plugins in a scratch folder with `-pluginsDirectory <path>`.

If you're an agent writing a plugin for the user, tell them which file you wrote and that they need
to reload, and don't edit plugins you didn't write unless they ask.
