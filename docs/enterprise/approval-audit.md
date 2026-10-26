# Approval audit, version 1

The host keeps a local, structured record of the ACP approval requests it observes and the decisions
it accepts. This first slice covers approvals only. It is separate from the recovery activity journal,
notifications, transcript replay, telemetry, Sentry and OTLP. It makes no outbound connections and has
no upload or UI action.

## Records and provenance

`HostApprovalAuditRecord` is the export schema. Each record contains:

- Schema version and a durable, increasing event sequence.
- Host and host-session UUIDs; host-generated request, action and option UUIDs. Request and action
  references identify this approval occurrence. They do not expose ACP request ids or tool-call ids.
- State: `requested`, `decided`, `withdrawn`, `deliveryAccepted` or `deliveryFailed`.
- The available option references and their ACP kinds (`allow_once`, `allow_always`, `reject_once`,
  `reject_always`, or `unknown`), and the selected option reference when one was chosen.
- Actor provenance: `localPeer` with the kernel-authenticated account uid, `pairedDevice` with the
  complete public device key proven by the handshake, or `unknown`. No display name is an identity.
- Source (`agent`, `direct`, `notification`, `host`), fixed reason codes, the host's existing managed
  policy revision (absent when unavailable or unmanaged), and policy mode.
- Wall time, host-process epoch and monotonic uptime in nanoseconds. Sequence orders records across
  process restarts. Uptime is comparable only within an epoch; wall clocks can change.

There is no tool title, command, prompt, path, argument, output, credential, option label, arbitrary
error string or client-supplied display text in these audit rows or exports. Raw option and tool-call
ids stay in the existing content-bearing approval table; UUID references keep them out of the audit.
After a decision, that table clears the title and option bindings and retains the session/tool-call
key as a first-wins tombstone until the session is deleted. Reusing a decided tool-call id in that
session receives a fixed RPC error, never a replayed decision. An agent must use a fresh tool-call id
for a new approval occurrence. Each request permits at most 64 distinct options. Unsupported option kinds
are explicitly unknown. A cancellation is a withdrawal, not a rejection or a selected approval.

The Unix accepting transport obtains the uid from the kernel, checks the same account, and retains
its existing code-signature checks on signed Mac hosts. The paired gateway passes the handshake's
public key with the registry's authoritative grants. RPC parameters cannot supply or replace the
actor. Connections admitted without authenticated provenance record `unknown`; they cannot export.
A uid identifies a local account, and a stable device key identifies a device. Neither proves the
person holding or using it. Notification actions use the same decision routine as direct responses.

## Commit and failure boundary

SQLite uses the host's existing WAL, `synchronous=FULL`, fullfsync and checkpoint_fullfsync settings.
Schema migration 11 adds approval audit event and head tables, and references in the existing
pending-approval table. No approval history is inferred for pre-migration rows.

1. The request audit event and pending row commit together before an approvable session event or
   notification is forwarded to any client.
2. The winning decision (or explicit client cancellation), pending-row transition and delivery-pending
   marker commit in one transaction before the selected answer is handed to the ACP peer. Competing
   or duplicate answers cannot claim that pending row again, including after a crash.
3. `deliveryAccepted` means the local transport accepted the write into its queue. It does not mean
   the agent received, acknowledged or executed it. A failed write records `deliveryFailed` with a
   fixed transport reason. No exception text is stored in audit or returned from these storage paths.
4. At startup, a previously requested approval becomes `withdrawn` with `hostRestarted`: its old ACP
   connection died. A decision whose delivery marker was still pending becomes `deliveryFailed`
   with `hostRestarted`, preserving the deciding actor. Delivery is uncertain, including when the
   write succeeded but saving its receipt failed. The host never replays a recorded decision.

Request or decision storage failure fails closed in every mode, including restricted deployments.
A failed request append forwards no approvable event and leaves the agent waiting. A failed decision
transaction leaves the pending row and live request unresolved and sends no answer. A failure after
commit cannot reopen a decision; clients receive a fixed delivery-uncertain error where possible.
A failed withdrawal clears the unanswerable live request; its durable requested row remains until
startup can record the withdrawal. If startup cannot commit audit recovery, host initialization fails.
This is not exactly-once agent execution. Power-loss durability relies on SQLite, the filesystem and
the storage device honoring their synchronization contracts.

Host policy remains authoritative: decisions require agent permission. Export uses the existing
files capability and local `manageHost`/`isLocal` grants, plus authenticated local-peer provenance.
No MDM keys or device grants are added. Under today's policy qualification, files and agents remain
unavailable in restricted mode; this slice does not qualify them for restricted execution.

## Local JSONL export

`NativeHostClient.approvalAudit(cursor:limit:)` calls `_native/audit/approvals/export`. Only an
authenticated local administrator may use it. Paired devices, even with management grants, and
unknown transports are refused. The host checks its own policy before reading RPC parameters.

A cursor is a host UUID and last consumed event sequence, beginning at zero. Pages contain only
typed approval records serialized as JSONL (ISO 8601 wall times), the next cursor, a high-water
sequence and `hasMore`. Limits clamp to 1...200 records; JSONL is capped at 256 KiB per page. Cursors
and sequences survive restart. The separate durable high-water counter lets export report missing
trailing rows as well as holes between records. A wrong-host, negative or future cursor returns
`invalidCursor`. Missing rows return `missingRange` with explicit inclusive bounds. A corrupt or
unreadable record returns `unavailable`, with no raw database or decoding error. Neither status
silently skips records: a gap page includes any verified prefix and its cursor stops at the last
exported event; an unavailable page returns the original cursor. A caller may explicitly resume
after a reported missing range;
that choice does not repair it. Export never queries content-rich activity/command journal rows.

No automatic audit retention, deletion or upload is introduced. Rows remain in the host database
until that database is removed or altered. Operators must account for growth and protection of local
exports. Same-account files are not tamper-proof: these records have no signatures, cryptographic
chain or external anchor. Missing-range reporting detects missing rows relative to the current
counter; it cannot detect coordinated rewriting of records and counters.

## Observed boundary and remaining work

ACP-omitted actions are unobserved. These records do not audit all tools, configuration changes,
exports themselves or general user activity. The existing host database, notification backlog and
recovery journal still contain content; this metadata-only export does not redact those other stores.
Older histories contain no reconstructed trusted approval actor.

Separate changes own the general event schema, tamper-evident checkpoints, durable collector outbox,
backpressure and retention choices, and routine-log redaction (audit plan C6-C8). Sentry and OTLP
are not durable audit stores. Approval evidence does not establish that a tool complied with policy
or that an agent reported every action.

## Evidence

`ApprovalAuditTests` exercises scratch databases and synthetic ACP agents through the client API:
request persistence before forwarding, direct and notification decisions, racing actors, duplicate
RPCs, restart before and after commit, transport disconnection, a lost delivery receipt, transaction
and read-only storage failures, withdrawal, cancellation, export authorization, pagination, gaps,
corruption and content canaries. It also uses the real local socket transport with a scratch host.
`GatewayIdentityTests` uses in-memory keys and socket pairs, proving identity survives display-name
changes and cannot be obtained by an unpaired key reusing the same name. These tests never use real
approvals, paired devices, installed hosts or user credentials.
