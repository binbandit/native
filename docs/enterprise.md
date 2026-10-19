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
- **Data, not code.** Policy is declarative and validated. A bad value is reported and ignored, never
  a crash or a lockout.

## Managed settings

Organizations deploy settings with their device management (Jamf, Kandji, Intune) as a configuration
profile for Native's bundle id. macOS exposes those as forced values in the app's defaults
(`UserDefaults.objectIsForced(forKey:)`), so no MDM-specific code is needed. iPadOS reads the same
keys from the managed app configuration dictionary (`com.apple.configuration.managed`).

`NativePolicy` (in `Packages/NativePolicy`, UI-free and tested) reads the `policy.*` keys below,
validates them, and publishes one value the app observes. The keys are documented in this file and
shipped as a sample `.mobileconfig` in `docs/enterprise/`.

| Key | Effect |
| --- | --- |
| `policy.agents.allowed` | Agent ids that may be listed or started; others are hidden with "Not allowed by your organization". |
| `policy.agents.environment` | Extra environment per agent, e.g. to route Claude Code through Bedrock or Vertex. |
| `policy.mcp.allowed` / `policy.mcp.blocked` | MCP servers by name or command pattern; blocked ones are denied for every session through the same session policy as the user's own switches. |
| `policy.mcp.required` | Servers every session gets, defined in the policy. |
| `policy.plugins.allowed` | Plugin ids that may load; **later:** required signer team ids for manifest plugins. |
| `policy.skills.blocked` | Skills by name, denied per session like MCP. |
| `policy.permissions.forbiddenModes` | Permission modes users can't pick (for example, modes that skip approvals). |
| `policy.scripts.enabled` | The V8 script runtime and `run_script`. |
| `policy.taskScripts.userScripts` | Task scripts written in Native, global and per project (`docs/scripts.md`): `false` stops them running and locks their settings. |
| `policy.taskScripts.repositoryScripts` | Task scripts committed to repositories as `.native/<event>.sh`: `false` ignores them and locks each project's "Run scripts from the repo" off. |
| `policy.labs.enabled` | Labs and experiments, including plugin experiments. |
| `policy.companion.enabled` / `policy.remoteHosts.enabled` | Pairing devices; connecting to hosts other than this Mac. |
| `policy.updates.feedURL` / `policy.updates.enabled` / `policy.updates.channels` | An internal update feed, or updates off; which channels are allowed. |
| `policy.search.retentionDays` | How long the search index keeps sessions. |
| `policy.shortcuts.bindings` | Keyboard shortcuts by command id, as Settings ▸ Keyboard Shortcuts exports them (`docs/commands.md`); they replace the user's changes and lock the page. |
| `policy.ai.instructions` | Instructions added to what Native writes with AI (titles, branch names, commit messages, pull request drafts, the prompts behind "Ask an Agent"), by purpose id: `title`, `branchName`, `commitMessage`, `commitGrouping`, `pullRequest`, `reviewRequest`, `pullRequestQuestions`. Native's format rules still come first. They replace the user's own instructions and lock Settings ▸ AI Instructions; a purpose it doesn't name gets none. |
| `policy.telemetry.native` | `on`, `off`, or `user` (the user chooses; the default). |
| `policy.telemetry.endpoints` | The organization's own collectors (see below). |

Every key also exists as a user preference where it makes sense. Precedence: the organization's value,
then the user's choice, then Native's default.

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

The durable host already keeps an activity journal: sessions started, prompts sent, approvals and who
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
