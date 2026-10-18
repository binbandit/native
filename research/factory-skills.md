# Skills: how Factory and the agents handle them

Research for Settings ▸ Skills (October 2026). Factory notes come from the read-only rebuild in
`~/developer/reverse/factory/factory-clone`; nothing of Factory's code, text or assets is copied
into Native. Agent mechanisms were checked against the adapters Native ships, and the two that
Native can switch were verified with real sessions (Codex on `gpt-6.1-sol`).

## The format everyone shares

A skill is a folder with a `SKILL.md`: YAML frontmatter, then Markdown instructions, plus any
scripts, references and assets beside it. The format is the Agent Skills spec (agentskills.io):

| Field | Notes |
| --- | --- |
| `name` | Required. 1-64 lowercase letters, digits and single hyphens; should match the folder |
| `description` | Required. What it does and when to use it; at most 1024 characters. Agents route on it |
| `license`, `compatibility` | Optional strings |
| `metadata` | Optional map (`version`, `author` often live here) |
| `allowed-tools` | Experimental: tools pre-approved while the skill runs |
| `disable-model-invocation` | Claude, Pi, Factory: only runs as an explicit command |
| `user-invocable` | Claude, Factory: false hides the slash command but keeps it for the model |

Agents put only names and descriptions in the system prompt and read the body when a task matches
("progressive disclosure"), so a missing or vague description is the most common real failure.
Strictness differs: Pi and Codex skip a skill without a description; Claude Code is lenient and
falls back to the folder name.

## Factory

- **Where skills live.** Built-in skills compiled into the CLI (wiki, reviews, office documents,
  its own "software factory" workflows). User skills in its own folder and the shared
  `~/.agents/skills`; project skills in the repo's equivalents; plugin skills from installed
  plugins; plus mission, automation and runtime sources.
- **One resolver.** Every surface resolves the same effective list. Names are normalized, a fixed
  source priority decides which copy wins, and each skill ends up Enabled, Disabled, Shadowed
  (another copy wins) or Invalid. Invalid skills are listed with their validation errors rather
  than hidden.
- **Enable and disable.** A list of disabled names in settings, at user, project or org level; a
  disable anywhere wins. The UI offers "for this project" or "across all projects". Files are
  never moved. Changes reach running sessions on the next turn (it re-reads every turn), and new
  skills are announced to the model mid-session.
- **Install.** There is no standalone skill installer and no skills registry. Skills arrive by
  dropping a folder in, by importing Claude Code's skills (a checklist that copies folders into
  Factory's own), by generating one from a prompt, or inside plugins from plugin marketplaces
  (git repositories with a manifest; GitHub shorthand, any git URL, local paths, pinned refs).
  The install flow picks a scope (user or project). There's no warning that skill scripts run code.
- **UI.** A two-pane browser: search plus filter chips by source (Project, Personal, Built-in,
  Disabled…) with counts; rows show name, description and a source badge; the detail pane shows
  the enable control with its scope, version and plugin tags, the rendered SKILL.md and the
  folder's other files. The terminal UI has tabs by source and sections Enabled / Disabled /
  Overridden / Invalid.

What Native takes from it: one resolved list with every copy accounted for, broken skills shown
with what's wrong, disable by name with a global and a per-project scope, files never moved to
disable. What Native does differently: it installs from git, folders and a real registry, shows
every script before writing anything, and switches skills for agents it doesn't own, through each
agent's own session or launch settings.

## The registry: skills.sh

`npx skills` (the `skills` npm package, vercel-labs/skills) is a cross-agent installer, and
skills.sh is its open index of skills in public GitHub repositories, ranked by installs.

- `GET https://skills.sh/api/search?q=<query>&limit=<n>` returns
  `{skills: [{id: "owner/repo/skill", source: "owner/repo", skillId, name, installs}]}`.
- `GET https://skills.sh/api/download/<owner>/<repo>/<skill>` returns the skill folder as text:
  `{files: [{path, contents}], hash}`. That makes a full preview possible before writing anything.
- The CLI installs into `.agents/skills` (the "universal" folder several agents read) and links or
  copies into agent-specific folders, recording sources in `skills-lock.json`.

Native uses the two endpoints directly (no Node needed) and never runs the CLI.

## The agents

| Agent | Reads skills from | Off without editing files | Verified |
| --- | --- | --- | --- |
| Claude Code | `~/.claude/skills` (or `$CLAUDE_CONFIG_DIR`), project `.claude/skills`, plugins' `skills/`, claude.ai synced skills in `~/.claude/skills/synced/<account>/` | Per session: `session/new` `_meta.claudeCode.options.settings.skillOverrides = {"<name>": "off"}` (the Agent SDK's flag-settings tier). Hides it from the model and the slash list. Plugin-qualified skills are not reached | Yes, claude-agent-acp 0.93.0: user and project skills disappeared from `available_commands_update`; `code-review:code-review` did not |
| Codex | `$CODEX_HOME/skills` (legacy), `~/.agents/skills`, project `.agents/skills`, bundled `$CODEX_HOME/skills/.system` | At launch only: `CODEX_CONFIG` env JSON, which codex-acp passes as every thread's config: `{"skills":{"config":[{"path":"<abs>/SKILL.md","enabled":false}]}}`. By file, not name, and per process | Yes, codex-acp 2.2.2 + `gpt-6.1-sol`: asked to list probe skills, it named both without the override and only the enabled one with it. The `$skill` command list still shows it (built from `skills/list`, which ignores thread config) |
| Cursor | `~/.cursor/skills`, project `.cursor/skills`, and for compatibility `.claude/skills`, `.codex/skills` (Cursor's docs) | None found | No: `cursor-agent` isn't installed here |
| OpenCode | project `.opencode/skill(s)`, `.claude/skills`, `.agents/skills`; `~/.config/opencode/skill(s)`, `~/.claude/skills`, `~/.agents/skills` (from the 1.19.3 binary) | Probably: a `permission.skill` rule set to `deny` through `OPENCODE_CONFIG_CONTENT` at launch | No, not wired yet |
| Pi | `~/.pi/agent/skills` (or `$PI_CODING_AGENT_DIR`), `~/.agents/skills`, project `.pi/skills` and `.agents/skills` up to the repo root | Only all-or-nothing (`--no-skills`) or exclusions in its settings files; pi-acp passes neither per session | Read from Pi 1.3.0's docs and pi-acp 0.0.34's source |
| Copilot | `~/.copilot/skills`, `.github/skills`, `.claude/skills`, `.agents/skills` (GitHub's docs) | None found | No: `copilot` isn't installed here |

Every agent re-reads skills only when a session starts (Claude also on `/reload-skills`), so
Native applies switches to new sessions and says that running ones change only when reopened (or
for Codex, when it restarts, which Native does once it's idle or when asked).
