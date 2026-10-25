# Managed adapter installer API

`NativeHost.ManagedAdapterInstaller` accepts the bytes of an explicitly trusted,
already-audited `package.json` / `package-lock.json` pair. It is not an auditor or
version resolver. A future caller loads a reviewed pair from signed app resources
(see [adapter-lockfiles.md](adapter-lockfiles.md)), supplies the relative JavaScript
entry point, login environment, arguments and working directory, and chooses an
absent destination under a stable, caller-owned parent. Untrusted remote manifests
must never be passed as audited input. The injected runner must use this host's filesystem.

The only network operation is `npm ci`, explicitly gated by `allowedByPolicy`:
callers must pass their effective managed-policy decision. Registry/mirror settings
come from the supplied npm environment/configuration and audited lock URLs; no
endpoint is built in. Offline or registry failures return an error without publishing
an install. There is no retry, update check, telemetry or adapter launch.

Installation uses a private sibling staging directory, a local npm cache, a five-minute
timeout and command-line `--ignore-scripts --no-audit --no-fund --global=false`.
`--include=optional` overrides inherited omission settings. npm checks lock integrity; both supplied
files must remain byte-identical. Output is discarded because it can contain secrets.
The entry must resolve to a regular file inside staging; absolute paths and traversal
are refused. An atomic exclusive rename publishes the complete directory, failing
if any destination appeared meanwhile (including an empty directory or symlink).
Linux needs libc `renameat2` and filesystem support for `RENAME_NOREPLACE`; unsupported
systems fail closed. Failure or cancellation observed before publication cleans only
this operation's staging directory. The atomic rename is the commit point.

The returned `AgentCommand` is `node <resolved-final-entry> <caller-arguments>`, with
the caller environment preserved and the install's `node_modules/.bin` prepended to
PATH. Existing `npx` launches remain unchanged until separate launch integration.
