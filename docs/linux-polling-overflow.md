# Capped polling file watches

Linux uses `PollingFileWatching` for the host's file change feed. Its default interval remains
2 seconds and each snapshot records at most 200,000 entries. Symbolic links are recorded without
traversing their targets.

If either compared snapshot is truncated, the watcher emits `FileWatchBatch(paths: [], isOverflow: true)`.
This includes an unchanged scanned prefix: editing an existing file beyond the cap need not change
the timestamps of any observed directory. Exact paths would claim coverage the watcher does not have.
Complete snapshots still return sorted changed paths, or no batch when unchanged.

The tradeoff is conservative invalidation every poll while the tree remains capped, plus the first
comparison after it fits again. Clients may rescan repeatedly even when nothing changed, while the
watcher's existing scan cap and polling interval stay in place. This replaces the older capped-prefix
behavior described in `durability.md`, where unseen edits could leave clients stale.

`PollingOverflowTests` covers unseen leaf edits, both coverage transitions, complete add/edit/delete
comparisons and a bounded stream check that waits for an overflow before editing. Run it and the
existing watch tests with:

```sh
nice -n 10 swift test -j 4 --package-path Packages/NativeHost --filter PollingOverflowTests
nice -n 10 swift test -j 4 --package-path Packages/NativeHost --filter FileWatchingTests
```

An inotify implementation and handling dropped stream-buffer batches are separate follow-ups.
