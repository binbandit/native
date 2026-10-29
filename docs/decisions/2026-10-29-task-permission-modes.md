# Shared task permission modes

Native uses four permission modes for all providers: Ask first, Accept edits, Auto and Full access.
New tasks default to Full access. Settings > General > New tasks sets the shared default; a project's
New tasks section can override it. Plainly Settings exposes the same values in New Tasks. The composer
changes only the current task. There is no experiment switch and no confirmation dialog.

| Native mode | Claude Code | Codex |
| --- | --- | --- |
| Ask first | `default` | `workspace-write`: on-request, user reviewer |
| Accept edits | `acceptEdits` | Same control as Ask first, with a visible fallback explanation |
| Auto | `auto` | `agent`: on-request, workspace-write, auto_review reviewer |
| Full access | `bypassPermissions` | `agent-full-access`: never, danger-full-access |

The Codex adapter's workspace mode permits workspace edits and commands. Its picker explains that
outside access asks. It does not claim a read-only sandbox. If Auto is unavailable for a Claude model,
Native uses Accept edits, or Ask first when edits are unavailable. Other ACP agents use recognized
permission controls through the plugin mapping. Unfamiliar values are never guessed from their order
or display names. A missing mode uses the closest stricter equivalent; choices with no safe equivalent
are disabled. Agents exposing no permission controls retain their own behavior and show a notice.

Provider mappings belong to plugins. `TaskPermissionMode` and `TaskPermissionMapping` in ACP hold the
UI-free contract and tested fallback logic. SessionModel presents the canonical values to shared Mac
and iPad views, while sending only the provider's value over ACP. The host journals the canonical intent
alongside the actual provider control and includes it in session summaries for paired clients. This
preserves distinct Native choices that share one provider control. Older clients can ignore that optional
field. Plan remains a task mode, separate from the four permission modes.

Saved task choices migrate to their closest Native mode. Existing workspace-write choices become
Accept edits; read-only and manual choices become Ask first. Unknown saved defaults become Ask first.
Provider-specific user/project defaults migrate once to shared keys. If several provider defaults differ,
the strictest explicit choice wins. Clearing a project override follows the shared default. Existing tasks
retain their chosen permissions when reopened; changing the default affects new tasks only.

Managed policy takes precedence over defaults and task choices. Native checks both canonical and legacy
provider identifiers, selects an allowed stricter mode, and blocks sending when no safe choice is active.
Switching agents retains the shared mode and applies the destination plugin's stricter equivalent.
The host reads the same managed cap itself and checks permission changes, prompts, steering and
hidden commands, so a paired client's local defaults cannot override it. Unknown provider controls
are refused under a managed cap. Tightening the cap pauses affected queues and ends active agent
processes that no longer satisfy it.

Full access does not suppress permission requests an agent actually sends. User-authored ask rules and
provider-enforced checks continue through the existing approval card and keyboard actions. Native does
not infer approval from the displayed mode or add a blanket approval bypass.

## Verification

Focused Swift Testing covers Claude/Codex mappings, conservative ACP fallback, unavailable modes,
policy exclusions, picker presentation and saved-default migration. Host integration coverage checks
shared intent after restart. Runtime checks and light/dark screenshots are recorded in the pull request.

Provider Plan and read-only controls remain available to task modes. They are separate restrictions, not additional permission choices in the composer. An organization that requires permission controls blocks sending with an agent that exposes none.
