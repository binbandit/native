# Agents

Notes on each built-in agent: how Native launches it, how it signs in, what it supports over ACP,
and its quirks. Every agent is a built-in plugin in `native/Plugins/`; the field names below are
`AgentManifest`'s (see `docs/plugins.md`). Capabilities are what each agent's `initialize`
response advertised when last verified, against a scratch ACP client that sends Native's exact
`initialize` (protocol version 1, the `subagents` client capability).

| Agent | Launch | Speaks ACP | Installed when | Sign-in |
| --- | --- | --- | --- | --- |
| Claude Code | `npx --yes @agentclientprotocol/claude-agent-acp@0.93.0` | Adapter | `claude` on PATH | `claude` (`/login`) |
| Codex | `npx --yes @agentclientprotocol/codex-acp@2.2.2` | Adapter | `codex` on PATH | `codex login` |
| Cursor | `cursor-agent acp` | Natively | `cursor-agent` on PATH | `cursor_login` over ACP, or `cursor-agent login` |
| OpenCode | `opencode acp` | Natively | `opencode` on PATH | None for its free models; `opencode auth login` for others |
| Pi | `npx --yes pi-acp@0.0.34` | Adapter | `pi` on PATH | `pi`, then `/login`; or provider API keys |
| Copilot | `copilot --acp` | Natively | `copilot` on PATH | `copilot login`, a token, or an existing `gh` login |

"Installed when" is the agent's `command` plus its `requires`: Native only starts agents that pass,
and offers the rest in Add Agent with their `setup.install` command (shown, never run).

## OpenCode

- **Launch:** `opencode acp`, the user's own `opencode` (Homebrew: `anomalyco/tap/opencode`).
  No adapter to pin; it reads the user's OpenCode config, providers and skills.
- **Verified** 2026-10-17 with OpenCode 1.19.3: `initialize`, `session/new`, `session/list`, and
  a prompt answered (`end_turn`) on the free `opencode/deepseek-v4.1-flash-free` model, both from a
  scratch client and in Native (new session, model switched in the composer, reply shown).
- **Capabilities:** `loadSession`; sessions `list`, `resume`, `fork`, `close`; images; embedded
  context; MCP over HTTP and SSE.
- **Auth:** one method, `opencode-login` ("Run `opencode auth login` in the terminal"), a terminal
  method. Its free `opencode/*` models need no sign-in, so a fresh install works signed out.
- **Quirks:**
  - Startup is slow: `initialize` took 2.5–11 s and `session/new` 6–26 s, while it refreshes its
    model catalog. Native's "Starting…" covers it.
  - `session/new` returns `configOptions` with every model of every provider (hundreds), plus
    `config_option_update` when one changes.
  - The default model is `opencode/big-pickle`, which in testing ran tools for a one-word answer
    and hadn't ended its turn after 5 minutes. Switching the model (`session/set_config_option`,
    `configId: "model"`) fixed it.
  - An expired provider OAuth token fails the prompt with JSON-RPC `-32603` "Token refresh failed:
    401", not `auth_required` (`-32000`), so Native shows it as an error rather than a sign-in.
- **Icon:** the OpenCode desktop app (`ai.opencode.desktop`) if installed, else registry `opencode`.

## Pi

- **Launch:** `npx --yes pi-acp@0.0.34`, with `PI_ACP_PI_COMMAND` resolved to the user's `pi`.
  Pi itself (`@earendil-works/pi-coding-agent`) does **not** speak ACP: it has its own JSON-RPC
  mode (`pi --mode rpc`). `pi-acp` (github.com/svkozak/pi-acp, MIT) is the adapter the ACP
  registry lists for Pi (`pi-acp`); it spawns `pi --mode rpc` per session and translates. Several
  forks exist on npm; the registry's is the one to track.
- **Verified** 2026-10-17 with Pi 1.3.0 and pi-acp 0.0.34: `initialize`, `session/new`,
  `session/list`, `session/set_config_option` and a prompt answered (`end_turn`), from a scratch
  client and in Native (on `openai/gpt-5.4-mini` with an API key, since the test Mac's OAuth logins
  had expired).
- **Capabilities:** `loadSession`; sessions `list` and `delete`; images; no embedded context
  (unless `PI_ACP_ENABLE_EMBEDDED_CONTEXT=true`); no MCP over HTTP or SSE.
- **MCP:** the adapter accepts `mcpServers` but doesn't pass them to Pi, so Native's orchestration
  tools aren't available in Pi sessions. Pi's own MCP (`~/.pi/agent/mcp.json`) still works.
- **Auth:** one method, `pi_terminal_login` (`type: "terminal"`, args `--terminal-login`), which
  launches interactive `pi` for `/login`. `authenticate` can't complete it over ACP. When Pi has no
  usable model, `session/new` fails with `auth_required` (`-32000`): "Configure an API key or log
  in with an OAuth provider." Provider keys in the login-shell environment (`OPENAI_API_KEY`,
  `ANTHROPIC_API_KEY`, …) count.
- **Quirks:**
  - **Expired OAuth fails silently.** With an expired provider token, a prompt ends `end_turn`
    in under a second with no reply and nothing on stderr. `pi -p` shows the real error
    (`refresh_token_expired`). Native shows an empty turn; a fix belongs in the adapter.
  - The adapter writes a "startup info" message (Pi version, skills, extensions) as the first
    `agent_message_chunk` of the first turn. `quietStartup: true` in Pi's settings turns it off.
  - The adapter keeps `~/.pi/pi-acp/session-map.json` so `session/load` can find Pi's session
    files; sessions only appear in `session/list` after their first prompt.
  - Requires Node 22+ for the adapter, and `pi` 0.81+.
- **Icon:** registry `pi-acp` (there's no Pi app).

## GitHub Copilot

- **Launch:** `copilot --acp`, the user's own Copilot CLI (`brew install --cask copilot-cli`, or
  npm `@github/copilot`). No adapter; the registry lists `@github/copilot` with `--acp`. The CLI
  auto-updates itself unless `COPILOT_AUTO_UPDATE=false`.
- **Verified** 2026-10-17 with Copilot CLI 1.0.98, installed in a throwaway prefix
  (`npm install --prefix /tmp/agents-test/copilot @github/copilot@1.0.98`) with
  `COPILOT_HOME` pointed at a temporary folder: `initialize`, `session/new`, `session/list` and a
  prompt answered (`end_turn`). In Native: not installed, it's absent from the sidebar and offered
  in Add Agent; after linking the throwaway `copilot` onto the PATH, Check Again found and started
  it without a relaunch ("Added Copilot."), and a session answered a prompt.
- **Capabilities:** `loadSession`; sessions `list` and `close`; `auth.logout`; images; embedded
  context; MCP over HTTP and SSE. Its built-in GitHub MCP server starts with every session.
- **Auth:** one method, `copilot-login`, with `_meta["terminal-auth"]` (`copilot login`).
  `authenticate` with it just answers `-32000` "Authentication required": sign-in only happens in a
  terminal. Signed out, `session/new` fails with `-32000`. Signed in comes from, in order:
  `COPILOT_GITHUB_TOKEN`, `GH_TOKEN`, `GITHUB_TOKEN`, a `copilot login`, or the GitHub CLI's
  existing login (verified: with no Copilot login, it used `gh`'s).
- **Quirks:**
  - `session/new` returns `configOptions` for mode (Agent, Plan, Autopilot), model and
    "Allow All", and sends `session_info_update` with a title after the first prompt.
  - It keeps state in `~/.copilot` (`COPILOT_HOME` moves it).
- **Icon:** GitHub Copilot for Xcode (`com.github.CopilotForXcode`) if installed, else registry
  `github-copilot-cli`.

## Claude Code, Codex, Cursor

Documented in their plugins (`native/Plugins/BuiltInPlugins.swift`, `CursorPlugin.swift`) and in
`docs/decisions.md`. Icons: Claude (`com.anthropic.claudefordesktop`) / registry `claude-acp`;
Codex (`com.openai.codex`, then ChatGPT `com.openai.chat`) / registry `codex-acp`; Cursor
(`com.todesktop.230313mzl4w4u92`) / registry `cursor`.

## What Native still needs for these agents

- **Terminal sign-in.** OpenCode, Pi and Copilot all sign in only in a terminal (`type: "terminal"`
  or `_meta["terminal-auth"]`). Native's Sign In calls `authenticate`, which can't complete these.
  Native should open the agent's command (`setup.signIn`, or the method's own `command`/`args`) in
  the user's terminal, then retry.
- **Pi's MCP.** Native's orchestration tools reach Pi only once `pi-acp` forwards `mcpServers`.

## Agent icons

Native never ships another product's artwork (`AGENTS.md`). An agent's `icon` (`AgentIconSource`)
is resolved at runtime by `AgentIconStore`, in this order, falling through when a step finds
nothing:

1. `path`: a plugin's own image file (SVG drawn as a glyph, or a bitmap), relative to its folder.
2. `apps`: the icon of the first installed app among these bundle identifiers, from Launch
   Services (`AgentIconInstalledApps`, the only AppKit code; iPadOS has no equivalent and skips it).
3. `registry`: the agent's icon from the official ACP registry. The index is
   `https://cdn.agentclientprotocol.com/registry/v1/latest/registry.json`, whose `agents[].icon` is
   a 16×16 monochrome SVG filled with `currentColor`. Index and icons are cached in
   `~/Library/Application Support/<bundle id>/AgentIcons/` (`registry.json`, `icons/<id>.svg`);
   icons refresh after a week, the index after a day, and cached copies keep working offline.
4. A monogram of the agent's name.

SVGs are drawn by Native's own small renderer (`native/AgentIcons/Glyph/`: paths, basic shapes,
groups, transforms, fill rules, strokes), so glyphs scale crisply, take the text color like SF
Symbols, and need no AppKit. SVGs with text, images or `<use>` fall back to the monogram.
Everything views draw goes through `AgentIcon(agent:size:)`. Menus only take an `Image` and ignore
SwiftUI's template rendering, so they use `AgentIconStore.image(for:size:scale:colorScheme:)`,
which draws glyphs in that appearance's label color; and macOS menus hide item icons unless the
menu's content (not the `Menu` itself) has `.labelStyle(.titleAndIcon)`.
