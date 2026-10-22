# Native

A native macOS app for running coding agents side by side.

Claude Code, Codex, Cursor, OpenCode, Pi, Copilot, and any agent a plugin adds. Each one runs as a
subprocess that speaks the [Agent Client Protocol](https://agentclientprotocol.com), and Native turns
those sessions into tasks, transcripts, approvals, goals and workflows. One window, many agents, no
agent-specific UI baked into the core.

<!-- Screenshots go in docs/images/. Add them here once they exist. -->
<!-- ![Native](docs/images/overview.png) -->

## What it does

- **Agents.** Bring your own. Anything ACP-compatible works, and new agents are plugins, built in or a
  `plugin.json` manifest. See [docs/agents.md](docs/agents.md) and [docs/plugins.md](docs/plugins.md).
- **Transcripts.** Streaming messages, tool calls, diffs, plans and approvals in one reducer shared by
  every client.
- **Subagents and orchestration.** Watch delegated work as it happens, and drive tasks from other
  tasks through the orchestration server.
- **Goals and workflows.** Give an agent a goal and let Native keep it going, or script a multi-step
  workflow.
- **Expeditions.** Big jobs for a crew of agents: a lead proposes a route, you approve it, and agents
  from any provider work through it with review checkpoints, ending in a debrief and a pull request. See
  [docs/expeditions.md](docs/expeditions.md).
- **Durable host.** Tasks live in a host process that outlasts the window, and the same protocol
  serves remote hosts and the iPad client. See [docs/durability.md](docs/durability.md).
- **Git and GitHub.** Status, diffs, commits, worktrees, pull requests and checks next to the task.
- **Terminal.** A real terminal built on Ghostty. See [docs/terminal.md](docs/terminal.md).
- **Labs.** Experiments you can switch on and off while they bake.
- **MCP and skills.** Native is an MCP client and server, and a sandboxed V8 script runtime lets agents
  run code over MCP. See [docs/script-runtime.md](docs/script-runtime.md).

## Requirements

- macOS 27 and Xcode 27.1 (the project targets the macOS 27 SDK).
- Optional, for the script runtime: [Rust](https://rustup.rs) (`cargo`).
- Optional, for the terminal: nothing to install. `scripts/build-libghostty.sh` fetches the Zig
  toolchain Ghostty pins.

When a tool is missing or a helper fails to build, the build warns and that feature is disabled
instead of failing the app.

## Build and run

With [just](https://github.com/casey/just) (`brew install just`):

```sh
just dev                              # installs the latest published main in ~/Applications, to use while it's built
just install                          # builds this tree's Release into ~/Applications, replacing the old copy
just build                            # a Debug build; `just build release` for Release
just run me                           # an isolated instance with its own settings and data
```

A fresh clone signs to run locally. To sign with your own team, put `DEVELOPMENT_TEAM = <team id>`
in `Config/Local.xcconfig`, which is never committed. Without just:

```sh
xcodebuild -project native.xcodeproj -scheme native -derivedDataPath /tmp/native-dd/me build
scripts/dev/run-isolated.sh me        # builds, launches an isolated instance, prints pid and window id
```

`run-isolated.sh` gives your instance its own bundle id, defaults and host, so it never touches your
daily Native. Tests live in each package:

```sh
(cd Packages/ACP && swift test)
```

## Repo layout

The map of folders and the rules for each one are in [AGENTS.md](AGENTS.md#map). In short: the app
lives in `native/`, UI-free logic in `Packages/`, the V8 helper in `Runtime/`, and design notes in
`docs/`.

## Docs

[Architecture](docs/architecture.md) -
[Decisions](docs/decisions.md) -
[Keyboard](docs/keyboard.md) -
[Product quality](docs/product-quality.md) -
[Releasing](docs/releasing.md) -
[Roadmap](docs/roadmap.md)

## Contributing

People and agents are both welcome. Start with [CONTRIBUTING.md](CONTRIBUTING.md), and read
[AGENTS.md](AGENTS.md) for the rules. Report security issues through [SECURITY.md](SECURITY.md).
By participating you agree to the [Code of Conduct](CODE_OF_CONDUCT.md).

## License

Native is [fair source](https://fair.io) under the [Functional Source License](LICENSE.md)
(FSL-1.1-ALv2). Read it, fork it, change it, use it at work, build on it: all welcome. The one thing
it rules out is shipping a competing product built from it. Two years after each release, that
release becomes Apache 2.0.

Geist (SIL OFL) and Ghostty (MIT) ship with their own notices.
