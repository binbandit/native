# Enterprise network transport qualification

A provider base URL or an environment variable is configuration, not proof of exclusive routing.
Unsandboxed agents can make auxiliary, telemetry, update, MCP and descendant requests. Native's
network inventory and `policy.network` are the policy vocabulary; only converted consumers enforce
it. See [network admission](network-admission.md) and [agent qualification](agent-network-matrix.md).
No new public endpoint, downloader, trust bypass or credential-store reader is added here.

## Transport matrix

| Transport | Trust and proxy behavior | Qualification in restricted mode |
| --- | --- | --- |
| NativeNetwork URLSession | System TLS verification; system proxy; one-hop redirect admission | Converted consumers only, currently agent icons |
| Other Foundation URLSession consumers | Per-consumer OS trust/proxy behavior | Unknown until individually migrated and fixture-tested |
| Sparkle | SDK trust, proxy, enclosure and release-note paths | Unqualified; whole SDK must be gated until all paths are admitted |
| Codex CLI 0.164.0 with codex-acp 2.2.2 | Rust CLI plus Node adapter, separate trust/proxy stacks | Unqualified and disabled; local fixture results do not qualify every path |
| Node/npm | Node trust and npm proxy/registry configuration | Separate job; no runtime installer permission implied |
| git/gh | Tool, helper, rewrite and environment-dependent trust/proxy/auth | Separate job; no foreign credential-store access |
| MCP HTTP/SSE/stdio | Independent transport/server and descendant behavior | Separate job; no inherited provider permission |
| Other agents | Vendor-specific endpoint/auth/update/telemetry and trust behavior | Unsupported pending exact pair qualification |
| Authenticated proxies | Credential references and proxy authentication | Unsupported by the candidate route translator |

## Fail-closed rules

Origins are exact scheme/host/port identities, with no credentials, paths, query, fragment or wildcard.
HTTP is allowed only for literal loopback fixtures. Host admission reuses NetworkOrigin and
NetworkAdmission, including service enablement, exact origins, air-gap restrictions and localIPC.
An unavailable or invalid network snapshot is denial. Proxy origins need their own explicit approval;
NO_PROXY is not an implicit permission to bypass a required proxy. Redirects require evidence for
each hop, including whether authentication headers cross an origin. Custom CA support must show
both valid-chain success and invalid-chain failure without disabling TLS verification.

Private route failure must remain a local failure, with no fallback provider, interactive login,
browser launch or public model discovery. No missing support becomes inherited permission. Runtime
credentials belong to the operator or Native-owned credential references; never put literal keys in
AgentSpec, policy, manifests, reports or logs. The candidate supports only a runtime variable
reference and does not implement Native credential hydration.

## Evidence limits

The headless fixture uses synthetic content, isolated homes, local HTTP/TLS/provider/proxy servers
and sandbox-exec enforcement. It first proves an unapproved local connection is denied. It does not
change the user's trust store or firewall and cannot approve itself. Missing enforcement, missing
artifacts, a failed fixture, unsupported CA/proxy controls or unobserved auxiliary traffic leave the
capability off. Linux and iPad transport qualification are separate jobs.

A loopback sandbox in a qualification fixture does not contain production agents. Customer-managed
OS and network egress enforcement is required for restricted deployments, including descendants,
DNS/proxy routing and host services. Phase E deployment acceptance remains a later gate.
