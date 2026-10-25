# Companion gateway identity storage

A Mac host's companion gateway has one long-lived secret: its Curve25519 identity, which paired
devices pin (`docs/companion.md`, "Identity"). Today it is the raw file `<host dir>/Link/identity.key`
(0600, in a 0700 folder). In a restricted deployment it belongs in the Keychain instead, with the
same public identity so no device has to pair again. `LinkIdentityMigration`
(`Packages/NativeLink/Sources/NativeLink/Identity/`) does that move.

This covers that one secret. It doesn't read or change `devices.json` or device grants, agent
credentials, or anything another application owns, and adds no cryptography, network access or
dependency.

## Status

The store and its migration are built and tested. The host helper still constructs its gateway
with the file store: it learns whether it is restricted from its own managed policy, which the host
policy work adds. Until that is wired, every host keeps `identity.key` exactly as before.

## Selection

`LinkIdentityMigration(directory:hostID:channel:restricted:)` is the gateway's `LinkKeyStore`.

- Ordinary host, no receipt: the existing file store (`FileKeyStore`), unchanged.
- Restricted host: migrates to the Keychain on first start, then reads only the Keychain.
- Any host with a receipt: follows the receipt, so a host that migrated stays on the Keychain after
  an authorized change back to ordinary mode. It never makes a file identity again.

## The Keychain item

One generic password in the user's login keychain, holding the 32 private key bytes. It follows
the convention of the host's agent keys (`HostKeychain`) under a service of its own, because
`HostKeychain` reads every item under `Native Host` as a credential.

| Attribute | Value |
| --- | --- |
| Service | `Native Host Link Identity`, or `Native Host Link Identity (<channel>)` |
| Account | The host's `HostID` |
| Synchronizable | No |
| Interaction | A context that doesn't allow interaction |

Every query names exactly that service and account and asks for one item. There is no wildcard
query, enumeration, update or delete, and no change to access control, access groups or signing.
It isn't the Data Protection keychain: that needs a keychain access group entitlement the host
doesn't have. The item is created by the host itself, so the host that made it reads it without a
prompt, the same condition `HostKeychain` relies on. A restricted deployment must confirm that its
signed host reads the item unattended.

## The receipt

`<host dir>/Link/identity-storage.json` records a version, the item's service and account, and a
phase. It holds no key material. The host derives the expected service and account from its own ID
and channel and refuses a receipt that names anything else, so editing a receipt can't point the
host at another item.

## Migration

The Link directory is opened one component at a time without following symlinks. Every ancestor
must belong to the user or root and not be writable by others (root's sticky `/tmp` aside), and the
Link directory itself must be private to the user. The legacy key and the receipt must be regular
files owned by the user, with no group or other access and a single link, and the key must decode.
Anything else stops with `unsafePath` or `invalidKey` before the Keychain is touched. The host's
location lock (one host per location) keeps two migrations from running at once.

1. Write a `creating` (no legacy file) or `importing` receipt, atomically and synced.
2. Read the item. A matching item is kept; a different one is a conflict. Insert only when there is
   none (a new host generates its key in memory and never writes it to disk). An insert never
   replaces an item.
3. Read the item back, compare public keys, and write `verified`.
4. Remove `identity.key`, sync the directory, and write `complete`. Only then does the gateway get
   its identity.

Every step resumes after a crash. Before `verified`, a restart compares the file and the item again.
From `verified` on, the Keychain is authoritative: a restart never reads, imports or regenerates
from the old file; it only retries removing it. After `complete`, a restart reads the receipt and the
item, and checks without opening it that no raw key file has reappeared.

## Failures

Each failure is a `LinkIdentityStorageFailure` code with no key bytes, file contents or paths:

| Code | Meaning |
| --- | --- |
| `keychainLocked` | The Keychain is locked, or reading would have needed a prompt |
| `keychainDenied`, `keychainUnavailable` | The Keychain refused or failed |
| `identityMissing` | The receipt says the Keychain has the key, but it doesn't |
| `conflictingIdentity` | The Keychain and `identity.key` hold different identities |
| `invalidKey`, `unsafePath`, `invalidMigrationState` | A key, path or receipt that can't be trusted |
| `migrationWriteFailed`, `legacyRemovalFailed` | The receipt couldn't be written, or the old file removed |
| `legacyCopyPresent` | A raw key file reappeared after the migration completed |

A failure stops the gateway from being constructed, so it never listens, advertises over Bonjour
or opens its control socket. There is no fallback to a file or a new key, and no retry.

## Administrator recovery

Stop the host, fix the cause, and start it again under the same host and channel.

- Locked or unavailable Keychain: restore access through the organization's usual process. Never
  change signing, access control or access groups to work around it.
- `conflictingIdentity`: keep both copies and the receipt. Decide which identity the paired devices
  trust through an approved process; the host won't pick one, overwrite either or unpair anyone.
- `identityMissing`: restore the original item. Importing an old file would bring back a key the
  receipt has already retired.
- `legacyRemovalFailed`: fix access to the Link directory; the verified item stays authoritative.
- `legacyCopyPresent`: find where the copy came from (a backup restore, an old host version) and
  remove it under the organization's data-handling procedure.

Don't delete or edit the receipt to switch back, and don't roll back to a host version that
ignores it: that version would make a new file identity. There is no automatic export or reverse
migration. Removing a file doesn't erase it from APFS snapshots, backups or SSD blocks; those belong
to data-lifecycle procedures. An abrupt stop during a receipt write can leave a
`.identity-storage-*.tmp` file with no key material, which is safe to delete while the host is stopped.

## Tests

`LinkIdentityMigrationTests` runs against a fake secret store and private temporary folders, never
a real Keychain: generation, an import that keeps the public key, an interruption at every step
(with and without a legacy file), matching and conflicting items, locked, denied and unavailable
Keychains, failed read-back, failed receipt writes and file removal, restart and a change back to
ordinary mode, corrupt keys and receipts, symlinks, path escapes, loose permissions, hard links,
and gateway construction failing closed. Receipts and errors are checked for a canary secret.
`ForeignCredentialBoundaryTests` admits exactly this new Keychain reader.

## Not covered here

This doesn't make every Native secret Keychain-only. Separate work remains for:

- Connecting the host helper to this store from its own managed policy, after the host policy work.
- The Mac client's per-host private keys and the Mac and Companion installation tags.
- MCP signing secrets, with rotation and removal of old copies.
- A general secret-reference contract, and scrubbing secrets from hydrated session records, the
  database and its WAL.
- Restricted credential storage on Linux hosts, through an approved OS secret store or a refusal.
