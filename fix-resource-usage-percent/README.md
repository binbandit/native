PR #108 visual check

Before: a60a125b85ca6018585b3a83d420115902b294cc, clean tree, isolated Debug build.
After: 94bb2a9ddf9f84a46d3416d38ba4ce5ad20cbb28, clean tree, isolated Debug build.
Instance: vc-108. Screen unlocked and target window uncovered for these captures.
GitHub uses the signedOut fixture. No projects or task content are loaded.

Reference: docs/architecture.md, Resource percentages. There is no separate design mock for this fix.

Observed: the before light capture shows a 101% total and one-core wording. After captures show machine-share readings in the status bar, groups, processes and total, including idle decimals. The expanded panel footnote fits in light and dark at 1100x760 and 820x660. Memory stays in MB. Collapse/expand and CPU sorting work. No visual correction was needed.

Tooltip wording was matched through the live accessibility tree with drive.sh find 'CPU percentages are shares'. The driver has no hover command, so the hover bubble itself was not photographed.

Validation: run-isolated.sh vc-108 --build; check-warnings.sh reports no repository warnings; nice -n 10 swift test -j 4 --filter ProcessCPUUsageTests passes all eight tests; swift format lint --strict passes all nine changed Swift files. No crashes were found for this instance.
