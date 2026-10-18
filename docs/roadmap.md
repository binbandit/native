# Roadmap

What's being built, who owns it, and where it stands. Owners are feature folders or packages; the
coordinator keeps this current.

## In progress

| Feature | Owner | Notes |
| --- | --- | --- |
| Git: status, diffs, commit, worktrees | `native/Git`, `Packages/Git` | Integrating into the app |
| GitHub: PR list, badges, create PR | `native/GitHub`, `Packages/GitHub` | Integrating into the app |
| Durable host, remote hosts, iPad client | `Packages/NativeHost` | Host protocol for every client |
| V8 script runtime, code mode over MCP | `Runtime/ScriptRuntime`, `Packages/ScriptRuntime` | |
| Experiments (Labs), bubble transcript | `Packages/Experiments`, `native/Experiments` | |
| Goals and workflows | `native/Automation` | |
| Usage limits, context breakdown | `native/Usage` | |

## Next

| Feature | Owner | Notes |
| --- | --- | --- |
| Smart commits | `native/Git` | Split changes into logical commits with drafted messages, reviewed before committing |
| Branch names from the task, with a prefix setting | `native/Git` | Prefix: GitHub username, custom, or none (as in the reference app) |
| Worktree or branch by default, automatic worktree setup | `native/Git`, models | Setup script, copying ignored env files, cleanup on archive |
| Archive and delete for tasks and projects | models, sidebar | Deleting a project never deletes its folder |
| Project icons: favicon detection and custom icons | sidebar | |
| Harness icons | plugins | Loaded at runtime from the installed app or the ACP registry, never vendored |
| Pi, OpenCode and GitHub Copilot agents | plugins | |
| `@` file mentions | composer | Fuzzy file search, sent as resource links; works through the host |
| Wispr Flow and dictation | composer | Full accessibility text contract on the composer |
| Native PR view and reviews | `native/GitHub` | Setting: open PRs in the browser or in Native |
| Automations | `native/Automation` | Scheduled and event-triggered tasks, run by the host |
| Remappable, searchable shortcuts and a command palette | new `Commands` feature | `docs/keyboard.md` stays the source of defaults |
| Code themes | design system | the reference app's set (Catppuccin, Tokyo Night, Gruvbox, Solarized, Dracula, Nord) plus popular ones |
| Terminal | new `Terminal` feature | libghostty |
| Updates and release channels | new `Updates` feature | Stable, beta, nightly; published as GitHub Releases |
| Startup performance | everyone, with a budget | First window well within one Dock bounce |
| Built-in skills, starting with "build a Native plugin" | orchestration (Native's MCP server) | |
| Code mode for other MCP servers | `native/MCP`, `Packages/MCPClient`, `Packages/ScriptRuntime` | A server marked "scripted" is reached through `run_script` instead of loading every tool schema (rea: 170 tools, ~197k tokens) |
| MCP OAuth for Native's own HTTP servers | composer, ACP | URL elicitation cards |
| One MCP switch across every agent | `native/MCP` | Session-scoped per-agent overrides, global or per project; no editing each agent's config by hand |
| Skills: browse, enable and disable, install, update and remove | `native/Skills`, `Packages/Skills` | One list across agents and scopes, in Settings ▸ Skills, as in the reference app |
| Minimal by default | plugins, settings | `docs/decisions.md` |
| Sounds stay quiet during Focus | `native/Sounds` | Waiting on Developer ID team signing: the Focus Status entitlement can't be added to ad hoc builds. The logic is built and tested; turning it on is step 8 of `docs/releasing.md`'s one-time setup |
| Celebrations plugin (Halloween, Día de Muertos first; international catalogue later) | `native/Celebrations`, `Packages/AppAppearance` | Spec: `docs/celebrations.md`. Engine, chooser and the two first editions now; the rest in reviewed artwork batches |
| iPad app | app target | After the host protocol lands (`docs/architecture.md`) |
| Expeditions (the reference app's missions, rebranded) | `Packages/Expeditions`, `native/Expeditions` | the reference app's concept under Native's own name, composed from orchestration, goals, workflows and worktrees |
