# Pinned component cache

`HostUpdater.PinnedComponentCache` delivers optional component bytes on Apple platforms. It has
no production consumer. Construction does no I/O; only `deliver(scriptingEnabled:downloadsAllowed:)`
can read or fetch. Disabled scripting returns nil before filesystem or network work. Downloads
default to false: offline requests reverify a pre-staged entry or return nil on a miss.

The caller supplies a private file-URL root, an independently trusted `PinnedComponent`, detached
signature, `UpdateSigningKey` and configurable HTTPS artifact URL. No descriptor supplies or replaces
the pin. The root's parent must already exist in a trusted, caller-controlled location; the cache
creates its root with mode 0700 after verification. An existing root must belong to the current user
and deny group/other access. Root and entry symlinks and non-regular entries are rejected using
descriptor-relative access. The root's ancestors must be trusted; this is not isolation from other
processes running as the same user.

The filename is the normalized SHA-256, independent of release labels or URL filenames. Every hit
passes `PinnedComponent.verify` again. Corrupt entries throw and remain untouched, without fetching
or automatic repair. An administrator can pre-stage regular files under their normalized hash names.

An allowed miss fetches, verifies size/hash/signature, checks cancellation, and atomically renames a
private, non-executable temporary file into place. Failed or cancelled deliveries leave no final
entry or temporary file and preserve other hashes. Cancellation is cooperative, checked immediately
before publication. The returned `Data` is the verified snapshot, not an executable path.

Components are capped at 128 MiB. The default URLSession transport accepts only successful HTTP
responses over HTTPS and streams at most the pinned byte count into memory. Injection reuses
`HostUpdateSource.Fetch`; custom transports must enforce successful HTTP status and bounded delivery.
Transport errors are reduced to `fetchFailed`, without credential-bearing URLs or response bodies.
The caller must derive both permissions from user choice and managed policy at request time. There
are no background requests, hardcoded endpoints, logs, archives, extraction or eviction.

These bytes are **not approved to execute**. Same-team code signature verification, sandbox
entitlements, notarized release artifacts, compiled production pins, policy/ScriptRunner wiring,
and removing bundled V8 remain separate work. The runtime remains bundled and unchanged. See
[component verification](component-verification.md) and [runtime boundaries](script-runtime.md#security-boundaries).
