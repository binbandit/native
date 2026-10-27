# Native tool context

Native's default agent-facing MCP payload was about 4,022 tokens per task before the first user
message. Supported agents now discover one skill instead. Its name and description cost about
33-36 tokens; conservatively including its full file location gives 48-69 tokens in this check.
Tool instructions and references load only when the skill is used. These are character-based
estimates of Native's incremental context, not tokenizer measurements or billed usage.

## Inventory before this change

Native automatically contributed one server, named `native`, over signed session-specific
loopback HTTP. It is shared by sessions, not one listener process per task.

| Source | What it adds |
| --- | --- |
| `Packages/MCPServer` | Generic HTTP transport, token signing, MCP protocol and tool listing. No tools of its own. |
| `OrchestrationPlugin` | App-served `native`: seven task tools, two guide tools, `setup_status`, and `run_script` when the embedded runtime and policy allow it. This is the default app configuration (`NativeHostTasks` is off). |
| `HostTasks` | When host tools are enabled, independently injects `native` at the host's address. Seven task tools, bundled guides when available, and setup/script tools relayed from the Mac app. A standalone host without app resources can have only the seven task tools. |
| `SetupTools` / `OrchestrationScriptTool` | Tools in that same server, not separate servers. Script listings may additionally name the user's configured script-mode servers. |
| Built-in agent `mcpConfig` | Claude Code: `claude-code`; Codex: `codex`; Cursor: `cursor`. These identify configuration formats for inventory and import; they do not install another Native server. Other built-in agents have no declared MCP configuration format. |
| `PluginRegistry`, `MCPServersPlugin`, `PolicyPlugin` | May additionally supply user-managed servers, enabled manifest plugins' servers and organization-required servers. Those variable, user-owned tool lists are unchanged and excluded from these numbers. |

Native handed its own server through ACP `session/new`, `session/load` and resume requests. It did
not write that server into Claude Code, Codex or Cursor's persistent configuration at startup.
`MCPLibrary.run` and `AgentCLICommand` change agent-owned servers only on an explicit settings
action through the agent's CLI (Claude `mcp add-json/remove`, Codex `mcp add/remove`). Cursor has
no such write command. Claude policy uses per-session settings; Codex policy uses launch-time
`CODEX_CONFIG` overrides. None of these paths is replaced for user-owned servers.

## Payload and schemas

[The complete capture](measurements/native-mcp-tools.json) contains every production tool's full
input schema, output schema, description and annotations, plus both server instruction strings.
The declarations in these four constructors are unchanged from baseline
`0257c27e36c71870e7357ca2de02bec6cb845545`: `OrchestrationTools`, `SkillTools`, `SetupTools` and
`OrchestrationScriptTool`. The capture uses the production constructors and embedded script runtime
from the isolated Debug app, with no user configuration, external server bindings or live agents.

| Tool | Compact declaration characters | Approximate tokens |
| --- | ---: | ---: |
| `list_agents` | 604 | 151 |
| `start_task` | 2,124 | 531 |
| `list_tasks` | 968 | 242 |
| `wait_for_task` | 1,676 | 419 |
| `get_task` | 1,060 | 265 |
| `send_message` | 1,210 | 303 |
| `cancel_task` | 1,095 | 274 |
| `list_skills` | 728 | 182 |
| `get_skill` | 500 | 125 |
| `setup_status` | 1,922 | 481 |
| `run_script` | 3,113 | 779 |

The complete `tools/list` JSON-RPC envelope is 15,056 characters. Host instructions add 781
characters, for 15,837 total (about 3,960 tokens). App instructions include setup and script
guidance, adding 1,030 characters instead: 16,086 total (about 4,022 tokens). Without `run_script`,
the listing is 11,942 characters. A host without either app tool has a 10,019-character listing
when the two bundled guide tools are available. Missing guide resources reduce it further.

Count method: compact JSON with `ensure_ascii=False` and separators `(',', ':')`, including the
JSON-RPC envelope, then add the decoded instruction string length and round up `characters / 4`.
Per-tool rows round independently, so their token sum need not equal the full-envelope estimate.
Provider formatting, generic skill tooling, system prompts, user/project instructions and other
MCP servers are outside this comparison. Dynamic script bindings can enlarge a task's listing.

Reproduce after building the isolated app:

```sh
scripts/dev/run-isolated.sh cx-mcp-to-skill --build
scripts/tests/native-tool-context.sh cx-mcp-to-skill docs/measurements/native-mcp-tools.json
```

## After

No Native MCP declaration or server instruction string is sent to a supported agent while the
skill can be delivered and MCP has not been opted into. The signed endpoint remains available
for on-demand CLI requests. All eleven actions use their existing handlers.

| Session | Before | After, skill delivered |
| --- | ---: | ---: |
| Claude Code, default app tools | ~4,022 tokens | ~36 for name/description; conservatively ~69 including the isolated installation path |
| Codex, default app tools | ~4,022 tokens | ~33 for name/description; ~48 including the default installation path |
| Agent without skill support | ~4,022 tokens | Same MCP payload |
| Explicit MCP opt-in | ~4,022 tokens | Same MCP payload, plus skill metadata when installed |

The frontmatter description is 120 characters. The namespaced Claude skill name and description
are 143 characters; the Codex name and description are 132. Using a normalized discovery line,
`- <name>: <description> (file: <absolute SKILL.md path>)`, the actual isolated Claude location is
274 characters in total (69 tokens), and the default Codex location is 191 (48 tokens). Paths are
measured locally but not copied here. Actual harness formatting varies. This removes about 98%
of Native's eager context in the measured configuration, without counting on MCP tool search.

Installation failures retain MCP unless the user explicitly disabled it. Shell sandbox approvals
still apply to CLI execution and loopback access. A user who needs MCP compatibility can turn it
on for that agent in Settings > Agents. Codex installation and thread credential routing are
covered by tests; no billed Codex task is used for verification.

Skill discovery references: [OpenAI's skill documentation](https://learn.chatgpt.com/docs/build-skills),
[Codex skill roots](https://github.com/openai/codex/blob/main/codex-rs/ext/skills/src/host_roots.rs),
[Codex shell identity](https://github.com/openai/codex/blob/main/codex-rs/protocol/src/shell_environment.rs),
[Claude SDK local plugins](https://code.claude.com/docs/en/agent-sdk/plugins), and the
[pinned Claude ACP adapter's session options](https://github.com/agentclientprotocol/claude-agent-acp/blob/v0.93.0/src/acp-agent.ts).
