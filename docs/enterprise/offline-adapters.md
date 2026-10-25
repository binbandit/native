# Offline adapter import API

`ManagedAdapterInstaller.importOffline` accepts a local directory and an independent
`OfflineAdapterBundle.Approval`. It never resolves versions, downloads tools, invokes
npx, repairs an install, or starts an adapter. Production host launch selection remains
unchanged. This API alone does not make a fresh Native installation air-gapped.

## Trust contract and format 1

The administrator approves the original `bundle.json` SHA-256 **outside the bundle**, plus
the reviewed package/lock bytes and deployment-owned Node/npm qualification. Loading a
checksum, key, or approval from the same imported directory does not establish trust.
Store the approval in signed Native resources or independently authenticated deployment
configuration. The importer uses the existing `NativeHostProtocol.ContentHash` primitive;
there is no new crypto implementation or dependency. That primitive currently fails
closed on Linux without CryptoKit. The host remains portable, but Linux offline import
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

## Administrator prestaging recipe

Choose one reviewed built-in lock pair and obtain every tarball through the organization's
separate artifact acquisition/review process. Do not run a resolver at import time. The
intended first pair is Pi `pi-acp@0.0.34`; its lockfile job must land before it can be named
as a released Native approval. This API does not promote an unmerged pair into trust.

1. Export the reviewed `package.json` and `package-lock.json` unchanged into `pair/`.
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
     --agent-version <qualified-version> --entry node_modules/pi-acp/<reviewed-bin-file>
   ```

   Replace every placeholder using the reviewed deployment qualification. The helper
   refuses existing output and missing or corrupt tarballs. Its printed manifest digest
   is a review candidate, not an approval. Repeating with identical inputs yields the
   same manifest bytes. Sign or distribute the approval independently after review.
5. Transfer the directory and approved metadata through the deployment's controlled
   channel. Create a new mode-0700 install parent. Pass `localInstallAllowed` from the
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

npm still verifies lock integrity. After `ci`, the importer requires unchanged pair and
manifest bytes, all required installed files, and a regular-file-only installed tree.
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

- Host launch selection and removing npx fallback in restricted mode.
- Reviewed built-in lock publication and complete agent/Node/npm distribution qualification.
- Catalog and skill install/activation receipts.
- Pinned component local import and executable qualification.
- A disconnected app/host installation and update set with release-owner integration.

The current script runtime remains embedded. Catalog index verification is not archive
installation, and the pinned component cache is not an executable installer. No app/host
updater, plugin installer, host policy loader or runtime delivery is included here.
