# Organizations and telemetry

How an organization rolls Native out to its developers and controls it, and how telemetry works for
us and for them. The policy layer and telemetry are being built now; everything marked **later** is
designed but not built.

## Principles

- **The user's work never leaves the machine through Native.** Prompts, transcripts, file contents,
  paths, commands, tool arguments and outputs are never part of telemetry. Agents talk to their own
  providers; Native adds no data path of its own.
- **One policy layer, read everywhere.** Every feature asks one `NativePolicy` whether something is
  allowed, rather than reading preferences ad hoc. An organization's managed settings feed it.
- **Managed means visible.** A setting an organization controls shows "Managed by your organization"
  and is disabled in Settings. Nothing is silently overridden.
- **Data, not code.** Policy is declarative and validated. A bad value is reported, never a crash.
  A bad *managed* value denies what it governs instead of falling back to a more permissive one
  (see [When a value is wrong](#when-a-value-is-wrong)).

## Managed settings

Organizations deploy settings with their device management (Jamf, Kandji, Intune) as a configuration
profile for Native's bundle id. macOS exposes those as forced values in the app's defaults
(`UserDefaults.objectIsForced(forKey:)`), so no MDM-specific code is needed. iPadOS reads the same
keys from the managed app configuration dictionary (`com.apple.configuration.managed`).

`NativePolicy` (in `Packages/NativePolicy`, UI-free and tested) reads the `policy.*` keys below,
validates them, and publishes one value the app observes. The keys are documented in this file and
shipped as a sample `.mobileconfig` in `docs/enterprise/`. [Policy coverage](enterprise/policy-coverage.md)
maps every key to the capabilities it governs and the code that honors it.

| Key | Effect |
| --- | --- |
| `policy.deployment.mode` | `ordinary` (today's behavior, the default), `internalOnly` or `airGapped`. See [Restricted deployment](#restricted-deployment). |
| `policy.network` | Which network services may run and the exact origins they may use ([network admission](enterprise/network-admission.md)). |
| `policy.organization.contact` | Help channel shown beside managed Appearance settings, for example #it-help. |
| `policy.appearance.codeTheme` | A built-in code theme id for both appearances. Unknown ids are reported and leave the user's own theme. Personal choices are preserved and return when the key is removed. Themes without a palette for one appearance use Native in that appearance. |
| `policy.appearance.codeTheme.reason` | Optional explanation shown when opening the locked code theme row. |
| `policy.agents.allowed` | Agent ids that may be listed or started; others are hidden with "Not allowed by your organization". |
| `policy.agents.environment` | Extra environment per agent, e.g. to route Claude Code through Bedrock or Vertex. |
| `policy.mcp.allowed` / `policy.mcp.blocked` | MCP servers by name or command pattern; blocked ones are denied for every task through the same task policy as the user's own switches. |
| `policy.mcp.required` | Servers every task gets, defined in the policy. |
| `policy.plugins.allowed` | Plugin ids that may load. Ordinary mode applies it to installed plugins; restricted modes to built-in ones too. **Later:** required signer team ids for manifest plugins. |
| `policy.catalog.enabled` / `policy.catalog.indexURL` | Inputs for the plugin catalog and its internal mirror ([catalog policy](catalog-policy.md)); no app consumer yet. |
| `policy.skills.blocked` | Skills by name, denied per task like MCP. |
| `policy.permissions.forbiddenModes` | Permission modes users can't pick (for example, modes that skip approvals). |
| `policy.scripts.enabled` | The V8 script runtime and `run_script`. |
| `policy.taskScripts.userScripts` | Task scripts written in Native, global and per project (`docs/scripts.md`): `false` stops them running and locks their settings. |
| `policy.taskScripts.repositoryScripts` | Task scripts committed to repositories as `.native/<event>.sh`: `false` ignores them and locks each project's "Run scripts from the repo" off. |
| `policy.celebrations.enabled` | `false` removes the Celebrations page and command, disables its plugin contributions, and restores the usual appearance. Personal choices are retained. Defaults to `true`. |
| `policy.organization.name` | Optional display name for managed notices, such as "Northwind Federal IT". Without it, notices describe this install without inventing an organization. |
| `policy.labs.enabled` | Labs and experiments, including plugin experiments. |
| `policy.companion.enabled` / `policy.remoteHosts.enabled` | Pairing devices; connecting to hosts other than this Mac (see [remote hosts](#remote-hosts)). |
| `policy.updates.feedURL` / `policy.updates.enabled` / `policy.updates.channels` | An internal update feed, or updates off; which channels are allowed. |
| `policy.celebrations.downloadsEnabled` / `policy.celebrations.baseURL` | Disable celebration artwork downloads (including index and signature), or mirror Native-signed packs internally. Cached and bundled icons remain available. See [celebration artwork](celebrations-artwork.md). |
| `policy.search.retentionDays` | How long the search index keeps tasks, in days since a task's newest known time; a task with no time is kept. A removed task's text, messages and history-file checkpoints all go, and the index file is compacted (at most once a day) so none of it stays on disk. |
| `policy.shortcuts.bindings` | Keyboard shortcuts by command id, as Settings ▸ Keyboard Shortcuts exports them (`docs/commands.md`); they replace the user's changes and lock the page. |
| `policy.ai.instructions` | Instructions added to what Native writes with AI (titles, branch names, commit messages, pull request drafts, the prompts behind "Ask an Agent"), by purpose id: `title`, `branchName`, `commitMessage`, `commitGrouping`, `pullRequest`, `reviewRequest`, `pullRequestQuestions`. Native's format rules still come first. They replace the user's own instructions and lock Settings ▸ AI Instructions; a purpose it doesn't name gets none. |
| `policy.telemetry.native` | `on`, `off`, or `user` (the user chooses; the default). |
| `policy.telemetry.endpoints` | The organization's own collectors (see below). |

Every key also exists as a user preference where it makes sense. Precedence in ordinary mode: the
organization's value, then the user's choice, then Native's default. A restricted mode ignores user
values for these keys.

### Where policy comes from

The organization's input is the only authority over these keys. On macOS that is a forced
preference from a configuration profile; on iPad, a key in the managed app configuration. Native
tells a key the organization doesn't set from one it set badly:

- On macOS, a forced key that a launch argument also names (`-policy.scripts.enabled YES`) can't be
  told apart from the argument, so it is treated as unreadable and denied.
- On iPad, a managed app configuration that isn't a dictionary makes every key unreadable, and
  Native denies everything optional.
- On both, `policy.*` keys Native doesn't know are reported, and lock a restricted mode down.

Each snapshot carries the state of the organization's input (absent, valid, invalid or
unavailable), a revision fingerprinting it, each key's validity and origin, and diagnostics that name
keys and problems but never values. `NativePolicy.inspection` reports all of it without content.

### When a value is wrong

A managed value Native can't use is logged (subsystem "Native", category "Policy") and the key takes
its most restrictive value: switches turn off, allowlists become empty, an unusable mirror or feed
turns its download off, unusable instructions or shortcuts lock Native's own. It never falls back
to the user's value or Native's permissive default. Retention fails closed by deleting nothing:
any period Native picked could remove what the organization meant to keep, so an unusable
`policy.search.retentionDays` keeps every task, ignores the user's own period and is reported
(and in a lockdown, with nothing readable, search keeps everything too). When the
value shapes agent sessions (`policy.agents.environment`, `policy.permissions.forbiddenModes`,
`policy.skills.blocked`, `policy.mcp.required`), agents are denied until it's fixed, and an unusable
`policy.mcp.blocked` blocks every server. Ordinary mode still keeps the usable entries of a list
with a bad entry, and reports the rest; a restricted mode rejects the whole list. Strings, numbers
and dates aren't Booleans: use `<true/>` and `<false/>`. Failing closed applies to the
organization's input: on a Mac with no profile, a user preference Native can't use is reported and
ignored, and never takes agents away. The exceptions are the network keys: an unusable
`policy.network` preference still stops Native's own connections, and an unusable
`policy.deployment.mode` preference means air-gapped ([network admission](enterprise/network-admission.md)).
Neither is ever remembered, so deleting the preference restores ordinary mode.

### Restricted deployment

`policy.deployment.mode` = `internalOnly` or `airGapped` turns on deny-by-default. In a restricted
mode:

- Every key is the organization's: user values don't apply, and a key it doesn't set takes its
  restricted value (features off, allowlists empty).
- A grant only takes effect for a capability whose code consults the policy decision before acting
  (`converted` in [policy coverage](enterprise/policy-coverage.md)). Today that is plugin
  activation, plugins' themes, icon sets and command knowledge, and agent icon downloads. Everything
  else is denied whatever the profile says. That denial only stops code that consults it: the
  plugin registry, which admits plugins and hands tasks their agents and MCP servers. Elsewhere a
  feature is off only where its own key's consumer reads the restricted value (updates, telemetry,
  remote hosts); one without such a switch, such as git or the terminal, doesn't check the decision
  yet and still acts. Schema coverage is complete; consumer integration is not.
- Built-in plugins are admitted like installed ones: listed in `policy.plugins.allowed`, with every
  capability they declare permitted. A plugin that doesn't declare its capabilities stays off.
- Keys Native doesn't know, an unknown mode, or a managed source it can't read deny everything
  optional.

Native remembers a restricted mode the organization deployed, outside its preferences. Removing
the profile, or a profile that can't be read, doesn't return it to ordinary mode: it stays
restricted with everything optional denied, across restarts. To leave, deploy a profile with
`policy.deployment.mode` = `ordinary`, let Native apply it once, then remove the profile.

Restricted modes are off unless deployed, and are not ready to advertise or rely on: they deny most
of Native, and don't yet stop every unconverted feature. Policy decides what Native itself starts; it isn't a sandbox for
agents and the tools they run (see the [regulated environments plan](plans/regulated-environments.md)).
An admin view of the effective policy, its origin and errors is a separate follow-up.

### Remote hosts

`policy.remoteHosts.enabled = false` turns off this Mac reaching other hosts: browsing the local
network for paired hosts, connecting and reconnecting to them, and pairing a new one by link or over
SSH. It wins over the user's own setting and over launch arguments. Native follows a change while it
runs: off stops browsing, closes every connection to a paired host and ends a pairing under way,
keeping nothing that pairing finishes afterwards. The pairings stay on this Mac, and each host's
agents and tasks keep running there. On again reconnects each pairing once, and tasks open here pick
up where they were. If Native started while it was off, on again takes effect at the next launch.

It covers only this Mac's outbound connections. Devices pairing with this Mac go through its
companion gateway, which `policy.companion.enabled` governs, and this Mac's own background host is
unaffected.

## Telemetry

Two independent streams built from one event model.

**Native's telemetry (for us).** Anonymous product usage that helps us decide what to build and fix:
which features get used, performance (launch time, hangs, memory), errors and crashes, and which agents
and versions are in use. It is opt-in: asked once, in plain words, after the user has used Native for
a while, never at first launch. The user can turn it off any time in Settings ▸ Privacy, and an
organization can force it off.

**The organization's telemetry (for them).** An organization can send the same events, and audit events
(below), to its own collector: OpenTelemetry over OTLP/HTTP, which their observability stack already
accepts. This works whether Native's own telemetry is on or off.

The event model (`Packages/Telemetry`):

- Events are typed (`TelemetryEvent`), with a fixed schema per event and an allowlist of fields.
  Free text is impossible by construction: values are enums, counts, durations and versions.
- A random installation id, rotatable, and never linked to an account. Organizations may add their own
  attributes (for example, a team name) for their own collector only.
- Batched, compressed, sent off the main thread when idle and on power, dropped after a bounded
  backlog. Nothing is sent while telemetry is off, and nothing is queued for later either.
- A local, readable log of what was sent (Settings ▸ Privacy ▸ "Show what Native sends").

| Destination | Default | Who controls it |
| --- | --- | --- |
| Native (us) | off until the user opts in | the user, or the organization (forced off or forced on) |
| Organization collector | none | the organization only |

Our destination is Sentry: errors, crashes, hangs and performance, plus the typed usage events. The
Sentry SDK starts only when consent and policy allow it, with default PII off, text-carrying breadcrumbs
off, no screenshots, view hierarchy or session replay, and a `beforeSend` allowlist.

## Audit

The durable host already keeps an activity journal: tasks started, prompts sent, approvals and who
gave them (including from which paired device), recoveries, update installs. It becomes exportable as
structured events through the organization's telemetry destination, with optional prompt and command
text **only** when the organization's policy explicitly turns that on for its own collector. Native
never sends that text anywhere itself.

## Later

- An organization plugin catalog: a signed index URL in the policy, so internal plugins (MCP servers,
  skills, workflows, themes) install for everyone and update together.
- Shared hosts for teams: Linux run boxes with per-user isolation and SSO or SSH-certificate sign-in.
- An admin view summarizing the policy in effect and why each managed item is set.
- A commercial license and support option alongside FSL for organizations that want one.

### Worktree base fetching

`policy.git.worktreeFetch` is a Boolean, allowed by default. Set it to `false` to prevent
Native from fetching a remote before it creates a task worktree. Worktrees then start from
the local commit and say so on the task. This key does not change user-authored script commands;
`policy.taskScripts.userScripts` and `policy.taskScripts.repositoryScripts` govern those.
The fetch uses only the repository-configured remote URL, has a 15-second deadline and falls
back to the local commit when offline.

## Command explanations and local coverage

`policy.approvals.knowledge` accepts a string containing a version 1 command knowledge JSON document.
The policy package validates each entry, reports bad values, and contributes only additive internal
tools. `policy.approvals.countUnknownPrograms` = `false` disables local unknown-program counts even
when the user enabled them. True permits the user choice; neither policy enables Fine print itself.
Counts never enter telemetry or exports and can be purged from Settings > Privacy. See
[command knowledge](command-knowledge.md) for the format, limits, and privacy contract.
