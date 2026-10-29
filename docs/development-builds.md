# Isolated build caches

`scripts/dev/run-isolated.sh <name> --build` keeps the app, host identity, build database, signing,
index and SwiftPM workspace private in `/tmp/native-dd/<name>`. Removing that instance does not
remove the reusable build caches. No app runtime or release settings change.

Shared data lives in `~/Library/Caches/native-build/isolated` (`NATIVE_DEV_CACHE` overrides it):

| Cache | Reuse and invalidation |
| --- | --- |
| `packages-v1/<graph hash>` | Successful builds publish immutable APFS clones of repositories, checkouts and binary artifacts. The key includes Package.resolved, local package manifests, the project and Swift toolchain. A new instance clones the snapshot into its own SourcePackages. SwiftPM JSON state and Git administrative paths are relocated before use. Modified dependency checkouts are never published. Publication is locked and atomic; readers never see a partial snapshot. |
| `xcode/<toolchain hash>/ModuleCache.noindex` | The compiler's shared module cache, keyed by Swift toolchain, SDK build and host architecture. |
| `xcode/<toolchain hash>/CompilationCache.noindex` | Xcode's content-addressed compile cache, bounded at 2 GB. Compiler inputs and flags determine reuse. Swift and Clang prefix mappings normalize source, product and derived paths across worktrees. Each instance still gets its own object files and linked app. |

Folder copies use `cp -cR`, sharing APFS data blocks without sharing writable inodes. Other volumes
fall back to a regular copy. A cache restore failure warns and lets Xcode resolve normally; failed
app builds never publish. There are no extra downloads or network probes in the cache helpers.
Package resolution retains the existing pinned versions and `-skipPackageUpdates` behavior.

Ghostty already shares its pinned Zig toolchain, sources, Zig cache and staged library in
`~/Library/Caches/native-build` (`scripts/build-libghostty.sh`). The Rust script runtime already
shares its Cargo target and checksum-verified V8 archive in `~/Library/Caches/Native/ScriptRuntime`
(`scripts/build-script-runtime.sh`). Those are reused directly; they are not copied into every
worktree. The scripts still control their own invalidation and signing.

`build.log` includes Xcode's build timing summary. `build-timings.txt` separates time waiting for a
build slot (including any disk-space wait) from time inside xcodebuild. Timing-summary task totals
are summed work across parallel tasks, not elapsed time. Run a build in one foreground call with a
long timeout; read the result once, rather than polling its log. Shared caches can be removed when
no builds are using them; do not remove another instance's DerivedData.
