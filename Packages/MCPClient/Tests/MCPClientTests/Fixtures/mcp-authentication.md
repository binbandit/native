# Authentication fixtures

`codex-mcp-signed-in.json` is the output of Codex CLI 0.164.0 `mcp list --json`, captured with an
isolated `CODEX_HOME`, file credential storage and synthetic OAuth credentials. The loopback endpoint
was replaced with `https://docs.example.com/mcp`. The wire value is `o_auth`; older `oauth` values
remain supported. No real account or token was used. `codex-mcp-list.json` supplies the existing
signed-out capture.

`codex-mcp-missing-bearer.json` was captured from Codex CLI 0.163.0 with an isolated `CODEX_HOME`
and file credential storage. Both an unset and an empty `NATIVE_MCP_FIXTURE_TOKEN` produced this
same `bearer_token` listing. Its loopback endpoint was replaced with the documentation URL.
That wire value describes the configured authentication method, not a usable token.

Claude Code and Cursor configuration leaves sign-in unknown until the agent reports it.
Native never opens their credential stores.

Tests never read the user's Keychain, run sign-in, refresh credentials or contact a remote server.
