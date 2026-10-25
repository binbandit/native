# Offline adapter import API

`ManagedAdapterInstaller.importOffline` accepts a local directory and an independent
`OfflineAdapterBundle.Approval`. It never resolves versions, downloads tools, invokes
npx, repairs an install, or starts an adapter. Production host launch selection remains
unchanged. This API alone does not make a fresh Native installation air-gapped.

## Trust contract and format 1

An `Approval` has three parts, none of them read from the bundle:

- The SHA-256 of the original `bundle.json`, which the administrator approves **outside
  the bundle**.
- An `OfflineAdapterBundle.ReviewedLock`: adapter ID, exact version and the SHA-256 of the
  reviewed `package.json` and `package-lock.json`. `ReviewedLock.pi` is built into Native
  (see [the built-in Pi pair](#the-built-in-pi-pair)); a deployment that reviews another
  pair supplies its own digests the same way.
- The deployment's Node/npm qualification: absolute paths, SHA-256 and exact versions.

The bundle carries the pair's bytes, but it can't choose them: a bundle whose pair differs
from the reviewed digests is refused, even when its own manifest and payload hashes agree.
Loading a checksum, key, or approval from the same imported directory does not establish
trust. Store the manifest approval and tool qualification in independently authenticated
deployment configuration. The importer uses the existing `NativeHostProtocol.ContentHash`
primitive; there is no new crypto implementation or dependency. That primitive currently
fails closed on Linux without CryptoKit. The host remains portable, but Linux offline import
qualification is pending; no process runs to work around missing verification.

`bundle.json` contains:

| Field | Meaning |
| --- | --- |
| `formatVersion` | Exactly `1` |
| `adapterID`, `adapterVersion` | Exact dependency pin from the reviewed pair |
| `os`, `architecture` | One qualified npm platform, such as `darwin` / `arm64` |
| `nodeVersion`, `npmVersion`, `agentVersion` | Exact deployment qualification, with no version ranges |
| `entryPoint` | Relative JavaScript file under `node_modules/` |
| `requiredInstalledFiles` | Entry plus every applicable locked package's `package.json`, including optional packages |
| `payloads` | Unique relative `path`, byte `size`, lowercase `sha256` for every payload |

The only payloads are `package.json`, `package-lock.json`, and npm content-addressed
archive bytes under `cache/_cacache/content-v2/sha512/aa/bb/<remaining digest>`.
There are no cache indexes, credentials, registry configuration, Node binaries, agent
binaries, executable installer scripts, app updates, or embedded runtime updates.
All ancestors of bundle/tool paths must be physical directories, not symbolic links.
Use canonical paths. Source directories and files must deny group/other writes and
set-ID permissions. Files must be regular, single-link files. Excess files and empty
undeclared directories are rejected. Input is bounded to 256 MiB and 20,000 files.

The complete directory is read through no-follow directory descriptors into a verified
snapshot before any process or staging write. Publication uses a private sibling stage
under an existing mode-0700 caller-owned parent. The caller must keep that parent and
qualified tool distributions stable throughout the operation. This is not protection
against another process with the same account or administrator privileges.

## The built-in Pi pair

`adapters/pi/package.json` and `package-lock.json` pin `pi-acp@0.0.34`, the version
`native/Plugins/PiPlugin.swift` launches, and `ReviewedLock.pi` names their digests.
`OfflineAdapterBundleTests` fails if the files and digests drift apart, and the Python
tests check the pair still audits offline and matches the plugin's pin. Changing the pair
means resolving and reviewing it again, then updating the digests in the same change.

The pair was resolved with npm 11.20.0 by
`python3 scripts/adapters/lockfile.py generate pi-acp 0.0.34 <new-dir>` with an empty HOME,
user and global npm configuration (no scripts, audit or funding). Two independent
resolutions, a day apart on different machines, produced the same records. Its 9 package
records (the adapter and 8 transitive packages, no optional or platform packages) were
reviewed for exact version, registry URL and canonical SHA-512 integrity:

| Package | Version | Tarball |
| --- | --- | --- |
| `@agentclientprotocol/sdk` | 0.26.0 | `https://registry.npmjs.org/@agentclientprotocol/sdk/-/sdk-0.26.0.tgz` |
| `cross-spawn` | 7.0.6 | `https://registry.npmjs.org/cross-spawn/-/cross-spawn-7.0.6.tgz` |
| `isexe` | 2.0.0 | `https://registry.npmjs.org/isexe/-/isexe-2.0.0.tgz` |
| `path-key` | 3.1.1 | `https://registry.npmjs.org/path-key/-/path-key-3.1.1.tgz` |
| `pi-acp` | 0.0.34 | `https://registry.npmjs.org/pi-acp/-/pi-acp-0.0.34.tgz` |
| `shebang-command` | 2.0.0 | `https://registry.npmjs.org/shebang-command/-/shebang-command-2.0.0.tgz` |
| `shebang-regex` | 3.0.0 | `https://registry.npmjs.org/shebang-regex/-/shebang-regex-3.0.0.tgz` |
| `which` | 2.0.2 | `https://registry.npmjs.org/which/-/which-2.0.2.tgz` |
| `zod` | 3.25.76 | `https://registry.npmjs.org/zod/-/zod-3.25.76.tgz` |

The review covers the lock records, not package behavior. `pi-acp` needs Node 20 or later
and runs the user's `pi`, so `agentVersion` is the Pi version the deployment qualifies.
Its entry is `node_modules/pi-acp/dist/index.js` (the lock's `bin`). The pair is not
copied into the app yet; existing Pi launches still use `npx`.

## Administrator prestaging recipe

Use the reviewed pair from the Native source of the release you deploy, and obtain every
tarball through the organization's separate artifact acquisition and review process. Do
not run a resolver at import time.

1. Copy `adapters/pi/package.json` and `package-lock.json` unchanged into `pair/`.
2. Supply each locked tarball in `archives/`, named `<sha512 hex>.tgz`, derived from its
   lock `integrity`. Include optional and alternate-platform records. Use an empty,
   deployment-owned directory, never a user's npm cache.
3. Qualify the already-installed Node, npm distribution and external agent version for
   the chosen OS/architecture. Record canonical absolute Node and npm CLI JavaScript
   paths and their SHA-256 digests. These two hashes identify the selected entry files;
   they do not attest the entire Node/npm distribution or qualify external agent behavior.
4. Create the directory bundle with the standard-library-only helper. It reads local
   files, calls the existing offline lock auditor, checks each tarball's SHA-512 against
   the lock, and writes a new output. It runs no subprocess and opens no socket:

   ```sh
   python3 scripts/adapters/offline-bundle.py /approved/pair /approved/archives /approved/bundle \
     --adapter pi-acp --version 0.0.34 --os darwin --architecture arm64 \
     --node-version <qualified-version> --npm-version <qualified-version> \
     --agent-version <qualified-version> --entry node_modules/pi-acp/dist/index.js
   ```

   Replace every placeholder using the reviewed deployment qualification. The helper
   refuses existing output and missing or corrupt tarballs. Its printed manifest digest
   is a review candidate, not an approval. Repeating with identical inputs yields the
   same manifest bytes. Sign or distribute the approval independently after review.
5. Transfer the directory and approved metadata through the deployment's controlled
   channel. The approval's lock is `ReviewedLock.pi`. Create a new mode-0700 install parent. Pass `localInstallAllowed` from the
   current effective local-install policy decision, separately from download permission.
   No download permission is needed or consulted by this local-only API.
6. Call `importOffline(from:approval:destination:localInstallAllowed:)`. The returned
   receipt contains a qualified absolute Node command and a receipt SHA-256. Retain that
   SHA-256 in trusted Native/deployment state. The API does not execute the command.
7. Before reuse, call `OfflineAdapterReceipt.reuse` with that retained digest, current
   approval and current policy. It rehashes the complete installed tree and tools and
   checks required files. An ID, directory name, or self-supplied receipt digest is
   insufficient. Failure leaves the material untouched for explicit administrator action.

## Process and failure contract

The subprocess receives a newly created HOME/TMPDIR and a PATH containing only the
qualified Node directory. No login environment, `NODE_OPTIONS`, user npm configuration,
cache, credentials or proxy settings are inherited. The qualified absolute Node runs
only its version probe and the supplied absolute npm CLI. npm's version probe and `ci`
use explicit offline, no-script, no-audit, no-fund, no-update-notifier flags, explicit
empty user/global config files, an isolated preseeded cache, and optional/dev/peer
inclusion. Bin links are disabled; callers use the direct JavaScript command.

npm still verifies every tarball against the lock's integrity. After `ci`, the importer
requires unchanged pair and manifest bytes, all required installed files, and a regular-file-only installed tree.
The cache and temporary configuration are discarded. A receipt binds the original
manifest approval, tools and every published file's size/hash. It is published with the
install in one exclusive rename. Existing destinations, including empty directories
and symlinks, are never replaced. Failed/cancelled imports remove only their stage;
the exclusive rename is the commit point. Repeating an import refuses the existing
destination; verified reuse is a separate operation.

npm failure or absent required installed files returns content-free `missingArtifact`.
No npm stdout/stderr, token, URL, registry response or user content is returned or logged.
There is no online retry. The offline npm setting is not an OS sandbox for arbitrary
qualified executable behavior; deployment controls still own process egress. The real
fixture additionally denies outbound transport with macOS sandbox-exec and observes
Node transport calls. It uses synthetic local tarballs and lifecycle marker scripts,
checks that no script/request occurs, and runs only a harmless fixture entry.

## Separate next PRs

- Host launch selection and removing npx fallback in restricted mode, including a managed
  local-install decision that stays separate from `agents.install` downloads.
- Agent, Node and npm distribution qualification, and reviewed pairs for the other adapters.
- Catalog and skill install/activation receipts.
- Pinned component local import and executable qualification.
- A disconnected app/host installation and update set with release-owner integration.

The current script runtime remains embedded. Catalog index verification is not archive
installation, and the pinned component cache is not an executable installer. No app/host
updater, plugin installer, host policy loader or runtime delivery is included here.
