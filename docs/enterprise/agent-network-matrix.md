# Agent private-provider qualification

No private-provider pair is enabled by this change. Restricted agent execution remains disabled by
HostPolicy, `agents.provider` remains an external-process inventory entry, and the host's approved
route list is empty. Ordinary launches without a route identity retain their existing behavior.
There is no Settings or composer switch that enables a private route.

## Contract and trust

Plugins declare `AgentNetworkCapabilities` for an exact CLI/adapter version. Missing declarations,
unknown controls, missing required controls and unknown versions are unsupported. The built-in Codex
plugin declares the candidate Codex CLI 0.164.0 / codex-acp 2.2.2 pair as unqualified. A manifest's
`qualified` value is not host approval. Qualification must be reviewed into a host-owned declaration;
client `AgentSpec` contains only a nonsecret route identity, not route configuration or credentials.

The host checks its own declaration, the complete expected launch spec, exact version identity,
required controls, every purpose, host policy and the current NativePolicy network snapshot before
launch. A missing network snapshot denies. NativeNetwork admission still refuses external-process
services in restricted mode. The host rechecks at its existing pre-spawn and post-initialize seams;
AgentLink independently rejects unapproved route identities before reading an environment. Denials
contain no endpoint, model, authentication reference, client name or adapter stderr.

Enabling this later also requires trusted executable/version/hash and controlled environment
admission (B1), offline verified adapter provisioning (B3/B4), a host-owned route/network policy
source, and preventing session-level model/provider/MCP changes. This PR does not supply those
controls and must not be enabled simply by changing `qualified` or populating a client declaration.
There is deliberately no production API for adding approvals. Linux rejects every private route
identity before launch; this job does not qualify its transport or import the Mac policy dependencies.

## Candidate configuration

`CodexConfigOverrides.environment(for:inheriting:)` creates one private Responses provider and model,
with `requires_openai_auth=false` and an operator runtime credential variable reference. It includes
no public-provider fallback or login command. It keeps the existing MCP and skills overrides in the
same document. Credential-bearing URLs, non-origin URLs and conflicting inherited settings fail
locally. Proxy, bypass, custom CA and Native credential references are unsupported by this candidate
translator and fail instead of becoming environment hints. No key is serialized, hydrated or read
from another application's stores. A runtime key is supplied only to the isolated fixture process.

`AppModel.composingPrivateRoute` requires a qualified plugin declaration and delegates configuration
to that plugin's translator. Today's candidate fails this gate. All agent-backed uses must select
the same admitted spec: conversation, title, commit, pull request, workflow and recovery. Host-owned
purpose coverage must include all six; a partial auxiliary route is not a grant. On-device title
models are a separate qualification, not evidence for this contract.

## Revision-bound evidence

The harness report records git revision, complete tracked diff hash, exact artifact hashes and
versions, observed fixture request metadata and blockers. It never records bodies, headers, tokens,
raw errors or real user configuration. Results are partial until every required cell passes and the
remaining host controls above are qualified. Documentation or translator tests alone cannot qualify
an executable.

| Control | Codex 0.164.0 / codex-acp 2.2.2 | Evidence |
| --- | --- | --- |
| Origin/model translation | Tested in package tests | AgentNetworkCapabilitiesTests |
| MCP/skills document preservation | Tested in package tests | AgentNetworkCapabilitiesTests and AdapterOverridesTests |
| Host versus forged client, exact versions, missing/unknown controls | Tested with fake launches | HostAgentRouteAdmissionTests |
| Revocation/restart and no denied launch side effects | Tested with scratch hosts | HostAgentRouteAdmissionTests and HostPolicyTests |
| Real private request and failed endpoint/model/auth | Blocked at session authentication preflight | Initial observation below |
| Redirect origin restriction | Blocked at session authentication preflight | Initial observation below |
| Proxy and bypass | Unsupported by translator; fixture observations only | No qualification grant |
| Valid/invalid custom CA | Unsupported by translator; fixture observations only | No qualification grant |
| MCP isolation, telemetry, self-update | Unqualified | Adapter 2.2.2 has the documented MCP precedence limit |
| Actual restart recovery and auxiliary route equivalence | Unqualified | Prompt-purpose samples do not establish restart or automatic title routing |
| Restricted launch | Disabled | Empty HostAgentRouteAdmission.approved; existing HostPolicy gate |

## Run the headless fixture

Use already installed exact binaries. Do not use npx or install missing artifacts. Pass the absolute
Node executable, Codex executable and installed adapter `dist/index.js`, plus a report outside the
worktree. On macOS, sandbox-exec denies network except exact fixture loopback ports and denies
reading the real home except the installed adapter package. A negative local-port probe must pass
before running the adapter. No machine-wide firewall, proxy, trust or installed-host setting changes.
A missing binary or failed enforcement probe is a blocker. TLS verification is never disabled.

```sh
python3 scripts/tests/enterprise-private-routing/qualify.py \
  --codex /operator/prestaged/codex \
  --adapter /operator/prestaged/codex-acp/dist/index.js \
  --node /operator/prestaged/node \
  --output /tmp/private-routing-qualification.json
```

The harness compiles the actual Swift translator, creates temporary HOME/CODEX_HOME and synthetic
credentials, and runs the real pinned adapter/CLI over ACP. It exercises local provider success,
endpoint/auth/model failure, a redirect trap, proxy/bypass, TLS roots and purpose samples. Browser,
login and tool requests are refused. Temporary homes and fixture processes are cleaned afterwards.
Exit 2 means unqualified, never a skipped success. Today's harness deliberately does not issue a
qualification receipt because MCP/auxiliary/restart/telemetry/update evidence is incomplete.

## Separate qualification jobs

| Transport or agent | Restricted qualification |
| --- | --- |
| Claude Code, Cursor, Pi, OpenCode, Copilot, manifest agents | Unsupported pending individual jobs |
| Foundation Models titles | Separate OS/model-availability evidence |
| Foundation URLSession and Sparkle | Separate trust, proxy, redirect and update-delegate tests |
| npm and adapter downloads | Separate lockfile/provisioning admission; never run by this harness |
| git/gh and helpers | Separate remote rewrites, credential and descendant evidence |
| MCP HTTP/SSE/probes/stdio and Native orchestration | Separate listener, destination and process admission |

Native's wrapper is admission, not containment of arbitrary descendants. Customer-managed egress
controls remain required. This matrix does not establish universal private-provider or air-gap support.

### Initial installed-pair observation

The controlled fixture for CLI 0.164.0 / adapter 2.2.2 reached ACP initialize but `session/new`
returned `Authentication required` before any provider request. Inspection of that installed
adapter shows `checkAuthorization` reads the app-server's startup auth requirement before the
session's CODEX_CONFIG provider override is applied. Supplying MODEL_PROVIDER does not bypass that
preflight. No authenticate or browser request was sent. This is a qualification blocker, not an
invitation to inject an OpenAI key or use a real account. Endpoint/model/auth failure, redirects,
TLS/proxy/bypass and auxiliary cases are blocked by session startup, not passing negative tests.

The [committed fixture report](../../scripts/tests/enterprise-private-routing/evidence.json) pins implementation
revision `ab49b17a4eef577e68265d0281da44373a1d0588` with an empty tracked diff, Darwin 27.2.0 arm64,
Node v26.12.1, and these installed artifacts:

- Codex CLI SHA-256: `d8990e3ee7acfbc26f91265b12a1a83f0fee40d0e0f8f1f40a37d4ec21f499cf`.
- codex-acp entry SHA-256: `6b1bb4e7e9caaf4aeca1042ae4aec2dc2433b0b0e4b1614b38a4d41699902aaa`.
- Node SHA-256: `7296c3dda88793e08d1089d839a782178c4bba6bb22f5c40ab2a75263fb071bd`.

Positive and negative fixture-port probes passed before the adapter ran. No real provider, user's
configuration or credential store was contacted. Subsequent documentation/evidence-only commits
do not change the qualification implementation. A future adapter change needs a fresh
full fixture run and host/executable/environment qualification before any approval is added.
