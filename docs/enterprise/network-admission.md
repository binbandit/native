# Network admission: inventory and first consumer

This is the A6/A7 boundary and the agent-icon integration, not complete restricted deployment
support. The planning baseline is 2026-10-25, `304cb6e8`. The signed catalog loader (#123), audited
adapter installer (#124), verified component cache (#125), foreign-credential removal (#120) and
celebration download policy (#109) remain separate controls. None establishes production-wide
launch or offline enforcement.

## Inventory versus integration

`NativeNetwork.NetworkInventory.runtime` is the executable service inventory. It supplies a stable
`NativePolicy.NetworkService` ID, named source owner, typed destination source, trigger, payload,
redirect policy, local/off-machine classification, offline behavior and integration status for every
entry. No separate hostname allowlist is maintained. Dynamic document/configuration destinations
are inputs for one service, never wildcard grants. `BuildNetworkInventory.entries` records builder
and release/operator activity separately; these IDs cannot receive runtime permissions.

All 36 runtime IDs have an allow/deny decision through `NetworkAdmission`. Only `icons.index` and
`icons.assets` actually use it in shipping code today. Other declarations explicitly say
`awaitingIntegration` or `externalProcess`. Calling the API for one of those in a restricted mode
returns `integrationRequired`; existing callers do not yet call it. Inventory completeness must
never be described as consumer migration completeness.

## Configuration

- `policy.deployment.mode`: `ordinary` (default), `internalOnly`, or `airGapped`.
- `policy.network`: one dictionary with optional `localIPC` Boolean and `services` dictionary.
- Each service entry requires `enabled` Boolean; optional `origins` is an array of exact origins;
  optional `endpoint` is a full primary URL whose origin must be in that same entry's `origins`.
- `localIPC` is true by default in ordinary mode, false in restricted modes. Literal IPv4 127/8
  and IPv6 `::1` also require this switch. `localhost`, LAN/tailnet names and IPv4-mapped IPv6 are
  not treated as literal loopback. Restricted mode also requires explicit service enablement and
  exact origins for HTTP loopback.

Example managed preferences (equivalent property-list dictionary):

```json
{
  "policy.deployment.mode": "internalOnly",
  "policy.network": {
    "localIPC": false,
    "services": {
      "icons.index": {
        "enabled": true,
        "origins": ["https://artwork.internal.example:443"],
        "endpoint": "https://artwork.internal.example/registry.json"
      },
      "icons.assets": {
        "enabled": true,
        "origins": ["https://artwork.internal.example:443"]
      },
      "diagnostics.native": {"enabled": false}
    }
  }
}
```

Ordinary mode preserves the existing index endpoint and cache/fallback behavior. A service with no
rule may use its declared configured/document destination. Supplying a rule constrains that service
to its exact origins, even in ordinary mode. `enabled: false` denies it in every mode. Internal-only
mode requires explicit service enablement and exact origins. Air-gapped mode denies every
non-loopback origin, including an explicitly configured internal mirror. It is not a LAN mode.

Managed values win. When either deployment mode or the network envelope is managed, user network
settings cannot supply missing grants. Unknown service IDs, unknown fields, numeric/string booleans,
invalid origins, partial rule entries, or malformed mode invalidate the whole network snapshot;
there is no fallback to a permissive user value. An unavailable snapshot also denies. Existing
non-network policy keys retain their current semantics; broader strict parsing is separate work.
Only the icon index consumes `endpoint` today; later consumers must select it explicitly.

## Transport contract

`NetworkClient` checks policy synchronously before invoking the injected one-hop transport. The
transport owns DNS/connect. URL parsing rejects embedded credentials, fragments, ambiguous numeric
addresses, scoped/encoded hosts, wildcards and unsupported schemes. Origins normalize DNS case,
default ports and IPv6 spelling; ports remain part of identity. HTTP is permitted only for literal
loopback. The HTTP client accepts only HTTP(S); the admission API also represents exact SSH/TCP/UDP
origins for future transport adapters. Local IPC is a separate destination type.

The production URLSession transport uses system TLS verification and proxy settings, without shared
cookies, credentials or URL cache. Its delegate refuses automatic redirects. The client admits each
manual hop, permits cross-origin redirects only when explicitly listed for that service, caps the
chain and validates the final origin. No automatic CDN, public mirror or fallback grants exist.
Errors expose only stable service IDs and reason codes; raw transport errors and URL contents do
not escape. Injected transports must obey the one-hop contract.

Current policy is read at admission, between hops, after completion and at publication. Defaults
updates also cancel in-flight tasks. Every observed network policy revision invalidates old receipts,
even if a transport ignores cancellation or policy is later restored. Consumers must commit cache
and model results inside the synchronous `publish` closure. Cancellation is cooperative; a request
already sent cannot be recalled. Policy delivery still depends on the OS supplying managed changes.
An unavailable source must return nil, not manufacture an ordinary policy.

## Icons and offline behavior

Both index and SVG requests use the boundary, including fresh/stale cached index URLs and weekly
background refresh. Cached SVGs, installed/bundled artwork and monograms remain available. A denied
miss never invokes the transport for the denied service and has no bypass retry. Index tasks are
invalidated when network policy changes. Non-default index endpoints use separate digest-named
cache files so a failed mirror cannot fall back to a public cached index. Receipt validation guards
cache writes and returning newly fetched bytes. Cached bytes are local data, not an egress grant.

## Conversion backlog

Each line is a separate later transport/consumer PR, using the inventory's source owner:

| Consumer / service IDs | Required integration |
| --- | --- |
| Celebrations: `celebrations.index`, `.signature`, `.assets` | Preserve existing download gate and signature/hash checks; admit all three paths and redirects. |
| Skills registry: `skills.search`, `.download` | Configure base, admit query/download and retries; retain local install. |
| Skill git: `skills.git` | Admit remote before staging; qualify git helpers and descendant enforcement. |
| MCP HTTP: `mcp.http` | Admit every tool request and redirect. |
| MCP probes: `mcp.probe` | Deny before health-check DNS/connect. |
| MCP SSE: `mcp.sse` | Recheck reconnect and cancel streams on revocation. |
| MCP stdio / orchestration: `mcp.stdio`, `orchestration.loopback` | Explicit local transport/listener grants plus subprocess policy. |
| Sparkle: `updates.app.feed`, `.assets`, `.notes` | Prove SDK delegates block every feed, enclosure and note request; otherwise disable the whole SDK in restricted mode. |
| HostUpdater: `updates.host.feed`, `.signature`, `.assets` | Production host policy source, admission, staging and redirect cancellation. |
| Diagnostics SDK: `diagnostics.native` | Whole SDK off in restricted mode until all sends/cache replays honor the boundary. |
| Organization diagnostics: `diagnostics.organization` | Admit each collector and queued resend; drop denied queues. |
| Git / gh: `git.remote`, `github.cli` | Admit configured remotes/hosts, qualify rewrites/hooks/helpers and subprocess policy. |
| GitHub avatars: `github.avatar` | Admit direct image URL and redirects; preserve cached image/placeholder. |
| External open: `external.open`, `agents.installGuides` | Gate before handing a URL/command to the OS or another process. |
| Catalog / components / adapters: `catalog.index`, `components.download`, `adapters.install` | Integrate explicit existing APIs with production policy; keep verified offline bytes separate from download permission. |
| Agent traffic / IPC: `agents.provider`, `agents.ipc` | Per-agent qualification and launch gating; no claim that Native constrains descendants. |
| Remote hosts: `hosts.connect`, `.pair`, `.discovery`, `.listener`, `.localIPC` | Gate DNS, reconnect, SSH, multicast and listener startup; close existing listeners on denial. |

An SDK that cannot honor the boundary must be wholly disabled in restricted mode until converted.
That is a conversion requirement, not a claim that current unconverted SDK startup is blocked.
Native's wrapper is not a sandbox for agent descendants, DNS rebinding, OS services, proxy routing,
or other processes. Customers still need OS/firewall/network enforcement and qualified provider,
proxy and trust configurations. Complete restricted deployment support is not advertised.

## Evidence

Use synthetic data and recording transports only:

```sh
nice -n 10 swift test -j 4 --package-path Packages/NativeNetwork --filter NetworkAdmissionTests
nice -n 10 swift test -j 4 --package-path Packages/NativePolicy --filter NetworkPolicyTests
scripts/dev/run-isolated.sh enterprise-network --build
scripts/tests/enterprise-network.sh
scripts/check-warnings.sh /tmp/native-dd/enterprise-network/build.log
scripts/check-ios.sh native/AgentIcons/AgentIconRegistry.swift
```

The model harness loads the isolated Debug library, never launches Native or the paired host, and
writes only temporary fixture caches. It covers denied misses, stale cached URLs, stale refresh,
permitted fetch/cache reuse, mirror failure and a cancellation-ignoring late response. Package tests
cover strict policy inputs, exact origins/ports/loopback, unknown services, zero transport calls,
redirect denial/final-origin mismatch and receipt revocation. GUI validation is outside this
headless job; no views or artwork change.
