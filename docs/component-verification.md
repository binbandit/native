# Component byte verification

`HostUpdater.PinnedComponent` is Apple-platform groundwork for optional components. It verifies
supplied bytes only. V8 remains bundled, and today's `ScriptRunner` and host installer are unchanged.
There is no production consumer or runtime download path in this change. Linux updater isolation
is tracked separately in PR #28; this API does not provide Linux component verification.

## Trust boundary

The caller supplies an independently trusted SHA-256 pin and expected byte count, intended to be
compiled into the app. The initializer requires exactly 64 ASCII hexadecimal digits (either case,
no whitespace) and a positive byte count. Both properties are immutable; the digest is normalized
to lowercase. `verify(_:signature:key:)` checks exact byte count, SHA-256, then a detached base64
Ed25519 signature using `UpdateSigningKey`. Success returns normally; failures throw the
component-specific `PinnedComponent.VerificationError` for invalid inputs, size mismatch, checksum
mismatch, or an invalid signature (including malformed signatures).

A downloadable descriptor, even one signed by the trusted key, must never supply or replace the
compiled pin. A different payload signed by that key with its own correct checksum still fails
against the compiled pin. This preserves the independent content constraint if a release source
or signing key is compromised, provided the app and its compiled pin remain trusted.

Verification performs no network, cache, filesystem, extraction, permission, or process operations.
The tests use only in-memory bytes and throwaway signing keys, including the signed replacement
case. Byte verification is never permission to execute: it proves content identity and signature
validity, not code-signing identity, sandbox confinement, notarization, or execution policy.

## Later integration

- Fetch only after scripting is enabled and policy permits it, using the app release's compiled
  pin. Disabled scripting must not fetch a component.
- Reuse a hash-keyed cache across app updates. Verify cached and newly fetched bytes against the
  trusted pin before use, and ensure the bytes checked are the bytes ultimately executed.
- Before execution, verify a valid same-team code signature and the required sandbox entitlements
  and restrictions. Preserve `ScriptRunner`'s sandbox boundary; its cached check assumes an
  immutable bundled helper and must be reconsidered for external cached artifacts.
- Handle signing and notarization of the delivered artifact in the release pipeline, along with
  publishing and compiling its independent pin. Byte verification does not establish notarization.

On-demand delivery, cache lifecycle, safe installation, executable permissions, execution, and
removing V8 from the app bundle are separate follow-up work. See [the lean-core plan](plans/lean-core.md)
and [script runtime security boundaries](script-runtime.md#security-boundaries).
