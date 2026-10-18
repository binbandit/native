# Skills

Settings ▸ Skills lists every skill the user's agents load, gives each one switch that applies
across agents, and installs, updates and removes skills. Research and the per-agent evidence are in
`research/factory-skills.md`.

## Pieces

| Where | What |
| --- | --- |
| `Packages/Skills` | No UI, macOS and iOS. SKILL.md parsing and validation (`SkillDocument`), where each agent reads skills (`SkillAgentFormat`, `ClaudePlugins`), scanning and grouping (`SkillScanner`, `SkillInventory`), switches (`SkillSwitches`, `SkillOffList`), installing (`SkillInstallSource`, `SkillInstaller`) and the skills.sh client (`SkillsRegistry`). Files go through `SkillFileSystem`, git through Exec's `CommandRunner`, HTTP through `SkillsHTTPClient`, so a host can serve all three |
| `native/Skills/Plugin` | `SkillsPlugin`: owns the `SkillLibrary`, contributes the switched-off skills to `SessionPolicy` |
| `native/Skills/Model` | `SkillLibrary` (observable state and every user action) and `SkillLibraryHost` (`AppSkillsHost` adapts `AppModel`) |
| `native/Skills/Views` | The page, rows, details, install and update sheets |
| `native/Plugins/*PolicyTranslator.swift`, `Packages/ACP/Sources/ACP/Adapters` | Each agent's translation of skill intents into its own mechanism (`ClaudeCodeSessionSettings`, `CodexConfigOverrides`, tested in ACP) |

## One list

Every agent's skill folders are read (user, open projects, Claude's account and plugin skills,
Codex's bundled ones). Folders several agents share, like `~/.agents/skills`, are read once and
credited to each agent. Copies are grouped by name, so a skill linked into `~/.claude/skills`,
`~/.codex/skills` and `~/.agents/skills` is one row listing three places and the agents reading
each. Problems are listed, not hidden: a folder without SKILL.md, malformed frontmatter, a missing
name or description, a name the spec rejects, a name that doesn't match its folder, and one agent
finding two different skills with the same name.

Native's own skills are in the same page, under Native's skills, each with its own switch. They're
Markdown files in `native/Orchestration/Skills/`, listed in `NativeSkill.bundled`, and each is a
symlink to the doc it is, so the skill and the doc can't drift:

| Skill | Doc | For |
| --- | --- | --- |
| `set-up-native` | `docs/setup.md` | Setting Native up for an engineer, on one Mac or several devices, and troubleshooting |
| `build-a-native-plugin` | `docs/plugins.md` | Writing a `plugin.json` that adds agents, MCP servers, workflows or themes |

The Orchestration plugin's `native` MCP server serves them with `list_skills` and `get_skill`, minus
the ones switched off for the calling session. Beside them, `setup_status` (`SetupTools`) reports how
Native is set up on the caller's Mac, read-only: Native's version and channel, each agent (state,
sign-in, reported version, launch and install commands), the durable host, paired devices, the
`policy.*` keys the organization manages, and updates. `AppSetupReporter` builds the report from the
models through `OrchestrationHost.setupReport`; its shape and text (`SetupReport` in
`Packages/NativeSetup`, tested there) carry nothing Settings doesn't show: no paths, environment
values, agent logs or transcripts. A new skill is a doc plus a symlink and an entry in
`NativeSkill.bundled`; Settings ▸ Skills picks it up from there.

## Switches

One switch per skill name, globally and per project (a project's beats the global one), stored in
`skills.json` in Native's Application Support folder. Switches never touch skill files or agents'
settings files. `SkillsPlugin` turns them into `SessionPolicy.disabledSkills`, and each agent's
plugin applies them its own way:

- **Claude Code, per session:** `skillOverrides` set to `off` in the session's settings, by name.
  Skills from Claude's plugins can't be reached; the row says so.
- **Codex, at launch:** `skills.config` entries in `CODEX_CONFIG`, by SKILL.md path, for skills off
  in every project (and project copies off in their own project). A switch for one project only
  can't reach Codex's user skills; the row says so. Codex restarts to apply it once none of its
  sessions is working, or right away with Apply to Running Sessions.
- **Cursor, OpenCode, Pi, Copilot:** no way found that leaves files alone; the rows and the
  folders footer say switches don't reach them.

Switches apply to sessions as they start. Running Claude sessions keep their skills until reopened.
Every switch can be undone with ⌘Z.

## Installing, updating, removing

Sources: a git URL or `owner/repo` (optionally `#ref`, or a GitHub `/tree/<ref>/<folder>` link), a
folder, or a skill from skills.sh (search in the sheet, or paste `owner/repo/skill` or its link).

1. **Fetch** into a staging folder (`git clone --depth 1`, or skills.sh's file listing). Nothing is
   written where agents look. Registry files with paths outside the skill are refused.
2. **Review:** the SKILL.md, every file with scripts first and marked, problems, and a warning
   when it has scripts. Choose agents and scope (every project, or one); the sheet shows the exact
   folders it writes. The fewest folders that reach every chosen agent are used: the shared
   `.claude/skills` and `.agents/skills` first, then agents' own.
3. **Install** copies the folder (without git history), records where it came from, and offers
   Undo, which removes what it wrote.

Update fetches the recorded source again, lists added, changed and removed files, and replaces
every copy on confirmation. Remove moves every user or project copy (or the link, never what it
points to) into Native's trash folder. Both can be undone from the page's notice.

## States

No agents that load skills; no skills yet (with Install); nothing matching the filter; reading; a
broken skill (Broken badge and the reason); duplicates (Duplicate badge); an agent a switch can't
reach (the row says which and why); a fetch that fails (the reason and Try Again); offline (fetch
and search say so); git missing (how to install it); a clash with an installed skill (refused,
nothing written); the Skills plugin turned off (warning).
