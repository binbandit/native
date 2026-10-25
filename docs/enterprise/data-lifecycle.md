# Data lifecycle

Where Native's data about the user's work lives, who owns each copy, and how retention, erasure and
legal holds are planned. `Packages/NativeDataLifecycle` holds the inventory in code, and the
[inventory](#inventory) below is rendered from it: `DataStoreInventoryTests` fails when this page and
the code disagree (regenerate with `NATIVE_UPDATE_DOCS=1 swift test --filter DataStoreInventoryTests`
in that package).

This is a planner and a contract, not a deletion feature. Nothing in the package removes, reads or
lists data, and no store has an adapter yet. Deletion and retention are **not** unified at runtime:
each store keeps the behavior its **Today** line describes until its own integration change lands.
`policy.search.retentionDays` still expires search index rows only, not agent histories, the host
database, automation files, worktrees, checkpoints or copies on paired hosts. Archiving a task is
not deleting it.

## Ownership

Every store has one of five owners, and only the first can ever be planned for removal by Native
alone:

| Owner | Meaning | What a plan does with it |
| --- | --- | --- |
| Native | Native writes it and is its only user | Plans it once the store has an adapter |
| external agent | An agent's own store (its history, configuration, sign-in) | Unsupported, unless that agent's plugin supplies an explicit adapter |
| customer | The user's or organization's: repositories, backups, tools, exports | Unsupported; listed so a result says it remains |
| operating system | Unified logging, crash reports, Notification Center | Unsupported; the system expires it |
| unknown | Nobody has established the owner (a repository Native cloned that the user may work in) | Unknown; never assumed to be Native's |

The inventory describes stores outside Native so a plan can name what it couldn't reach. Native
doesn't read them to inventory them, and never reads another app's secrets.

## Planning

`DataLifecyclePlanner` is a pure function. Its inputs are all supplied by the caller:

- the inventory (`DataStoreInventory.native`);
- a `DataLifecyclePolicy` built from a validated `NativePolicy`, with its revision;
- a `LegalHoldAuthority`: a confirmed set of holds (possibly empty), or unavailable;
- the roots the caller approves (`DataApprovedRoots`), as absolute plain paths for file-backed
  kinds only. A store a setting has moved (`automationDataDirectory`, `pluginsDirectory`,
  `gitWorktreesFolder`, `pullRequestTasks.cloneFolder`) is approved as a `userChosen` root named
  by that setting, and only its own copies match there;
- which adapters exist and what they can do (`DataAdapterSupport`, empty today);
- the tombstones kept so far;
- what each store's owner listed (`DataStoreReport`): records by opaque id, with their parents,
  timestamps and copies, each copy's path under an approved root, its reported owner, link state,
  availability and the other records sharing it;
- the clock: the time now and the latest time already trusted.

It never touches a file, the network, a process or a timer, and never infers permission or
ownership from a path. A path is components under an approved root, checked lexically: no empty,
dot or separator components, and it must fall where the inventory says the store keeps that copy.
Whether a path is a symbolic link is the owner's report, not something the planner looks up.

### Precedence

For each copy of each record in scope:

1. **A confirmed legal hold wins.** A hold names everything, some stores, or records; a hold on a
   record also covers the records that belong to it (a project's tasks) and any copy it shares.
   What any listing says a record belongs to counts in every store, so one store that doesn't know
   a held parent can't release the record or a copy it shares.
   Held copies are reported held whatever retention or a request says.
2. **Otherwise a record is due** because an erasure names it or one of its parents, its tombstone
   says it was removed before and it has come back, or a policy retention period has expired.
3. **A due copy is planned only when nothing stands in the way**, and every obstacle is reported,
   not just the first: an unavailable policy or hold authority, a malformed hold set, unknown
   integration, an owner that is unknown or doesn't match the inventory, a missing, escaping or
   misplaced path, a symbolic or unknown link, an unapproved root, an offline or unknown host,
   another record still using the copy, or an adapter missing a capability the copy needs.

Each outcome is planned, kept, held, unsupported, unreachable or unknown, with its reasons, the
adapter capabilities it needs and a stable operation id. The plan carries the policy revision and
the hold revision it honored.

### Failing closed

- **Holds.** Native has no hold source of its own yet. "No holds" has to be confirmed by the caller;
  an unreadable source, an empty revision, an empty or duplicated id, or a hold naming nothing makes
  every due copy unknown.
- **Policy.** An unavailable or locked-down policy plans nothing destructive. A retention value the
  organization set badly is `unusable`, and nothing is due by it. This differs from the policy
  layer, which gives an unusable `policy.search.retentionDays` one day (the most restrictive value
  for keeping data); for deletion that is the most destructive, so the planner refuses it. The
  search integration has to reconcile the two.
- **Time.** Age is the newest timestamp the owner knows, in whole days of 86,400 seconds, as search
  counts them. A record last active exactly at the cutoff is kept. A record with no timestamp, one
  newer than the planning time, or any record while the clock is behind the last trusted time is
  unknown rather than due. An erasure request doesn't depend on the clock. A clock running fast is
  not detectable here; the caller supplies the trusted floor.
- **Coverage.** A plan is `complete` only when every copy in scope is planned or not due and every
  store in scope was listed. A store nobody listed, one whose listing failed or names a record
  twice or without copies, one outside Native or one whose integration is unknown is named in
  `unaccounted`, and the plan is `partial` or `blocked`.
  With the real inventory an erasure is never complete today: agent histories, customer backups and
  the system's records always remain, and every result says so.
- **Sharing.** A copy several records use goes only when all of them are going, and a hold on any of
  them keeps it.

### Identifiers and tombstones

An operation id is a digest of the request id, store, record, copy kind and location, so planning
the same request again yields the same operations to resume. The plan id also covers the policy
and hold revisions and every outcome, so an executor can tell a plan has gone stale; it doesn't
depend on the time. Stores that something can repopulate (search from agent histories, the session
catalog from agents' own listings) need a tombstone written with the delete. A record a store lists
again despite its tombstone is planned for removal again, and `DataTombstoneLedger.permitsImport`
lets a reindex skip it.

## Adapter contract

`DataStoreAdapter` is the narrow contract a store's integration implements: `estimate`, `export`,
`delete` and `verify`, for operations taken from a current plan. Capabilities are declared, and a
copy whose adapter lacks one stays explicitly unsupported. An adapter:

- acts only on operations from a plan whose policy and hold revisions still hold, and re-checks
  holds before each destructive step;
- is idempotent by operation id: a crash resumes rather than repeats, and a copy already gone
  verifies as removed;
- writes the tombstone in the same transaction as the delete for a store that can be reimported;
- reports what remains past its reach (`DataResidue`: log frames, free pages, unreachable git
  objects, storage blocks, customer backups) instead of claiming an erasure the storage can't
  guarantee. Unlinking a file frees its blocks; it is not secure erasure on an SSD. There is no
  generic recursive remover: each adapter removes only its own store's records.

### SQLite stores

The host database and the search index run in WAL mode. A deleted row stays in the write-ahead log
until a checkpoint, and in freed pages until a vacuum or `secure_delete` overwrites them. A host or
search adapter must:

- delete a record's rows from every table that holds them and write its tombstone, in one
  transaction;
- then run `PRAGMA wal_checkpoint(TRUNCATE)` and confirm it completed (a busy reader can keep it
  from truncating), and either `VACUUM` or keep `secure_delete` on, reporting `freePages` until one
  has run;
- verify by querying for the record after the checkpoint, and resume by operation id after a crash
  at any point;
- serialize with the store's own writers and its automatic pruning, which must consult holds too.

The host database also gains the approval audit. Audit records are a natural hold target and may
carry their own minimum retention, so the host adapter has to decide what an erasure request does
to a task's audit rows (keep them, or reduce them to ids) before it deletes anything.

## Integration sequence

Each step is its own change, with its own tests, in this order. None of them is done yet.

1. `lifecycle-host-database`: the host's SQLite and WAL, its automatic pruning made hold-aware, and
   the conflict between erasure and the approval audit.
2. `lifecycle-search`: the search index with tombstones, so a reindex from agent histories can't
   restore an erased task; retention that also removes `sources` rows, checkpoints and vacuums, and
   treats unknown times and unusable policy as the planner does.
3. `lifecycle-automation`: automation, workflow and expedition files and expedition documents.
4. `lifecycle-app-records`: the session catalog, drafts and other content-bearing preferences,
   usage, attachments, temporary files, pull request artifacts, skills trash and caches.
5. `lifecycle-external-agents`: explicit adapters only for agents whose own interface supports
   exporting or deleting their history, declared by their plugins. Everything else stays
   unsupported and listed.

Later: `lifecycle-git` (task worktrees and Native's refs, never the user's objects or reflogs),
`lifecycle-secrets` (Native-owned credentials and pairings, with the secret-reference work) and
`lifecycle-remote-hosts` (planning on a paired host through its own planner, offline hosts
reported unreachable). A later `enterprise-retention-UI` change, on a machine with a display, shows
the dry run: scope, holds, every non-planned outcome with its reason, unaccounted stores, failures
and completion evidence. The planner's results are what it shows.

## Inventory

<!-- inventory:begin -->
| Store | Owner | Records | Delete | Hold | Follow-up |
| --- | --- | --- | --- | --- | --- |
| `host.database` | Native | session | adapter pending | pruned automatically, ignoring holds | `lifecycle-host-database` |
| `host.runtime` | Native | host | - | - | - |
| `host.credentials` | Native | agent | adapter pending | user deletes ignore holds | `lifecycle-secrets` |
| `host.pairingIdentity` | Native | device | adapter pending | user deletes ignore holds | `lifecycle-secrets` |
| `orchestration.tokenSecret` | Native | host | adapter pending | - | `lifecycle-secrets` |
| `host.updates` | Native | host | - | - | - |
| `remote.hostCopies` | Native | session | adapter pending | pruned automatically, ignoring holds | `lifecycle-remote-hosts` |
| `audit.approvals` | Native | approval | adapter pending | not determined | `lifecycle-host-database` |
| `app.sessionCatalog` | Native | session | adapter pending | user deletes ignore holds | `lifecycle-app-records` |
| `app.drafts` | Native | session | adapter pending | user deletes ignore holds | `lifecycle-app-records` |
| `app.sessionState` | Native | session | adapter pending | pruned automatically, ignoring holds | `lifecycle-app-records` |
| `app.projects` | Native | project | adapter pending | user deletes ignore holds | `lifecycle-app-records` |
| `app.repositoryTrust` | Native | project | adapter pending | user deletes ignore holds | `lifecycle-app-records` |
| `app.settings` | Native | store | adapter pending | user deletes ignore holds | `lifecycle-app-records` |
| `app.usage` | Native | session | adapter pending | pruned automatically, ignoring holds | `lifecycle-app-records` |
| `app.policyEnrollment` | Native | store | - | - | - |
| `mcp.servers` | Native | store | adapter pending | user deletes ignore holds | `lifecycle-app-records` |
| `mcp.secrets` | Native | store | adapter pending | user deletes ignore holds | `lifecycle-secrets` |
| `pairing.hosts` | Native | host | adapter pending | user deletes ignore holds | `lifecycle-secrets` |
| `pairing.companion` | Native | host | adapter pending | user deletes ignore holds | `lifecycle-secrets` |
| `search.index` | Native | session | adapter pending | pruned automatically, ignoring holds | `lifecycle-search` |
| `automation.store` | Native | automation | adapter pending | pruned automatically, ignoring holds | `lifecycle-automation` |
| `expeditions.store` | Native | expedition | adapter pending | user deletes ignore holds | `lifecycle-automation` |
| `expeditions.documents` | Native | expedition | adapter pending | user deletes ignore holds | `lifecycle-automation` |
| `temp.attachments` | Native | session | adapter pending | user deletes ignore holds | `lifecycle-app-records` |
| `temp.workingFiles` | Native | store | adapter pending | pruned automatically, ignoring holds | `lifecycle-app-records` |
| `github.pullRequestQuestions` | Native | pullRequest | adapter pending | user deletes ignore holds | `lifecycle-app-records` |
| `github.pullRequestClones` | unknown | repository | outside Native | owner outside Native | - |
| `git.taskWorktrees` | Native | session | adapter pending | user deletes ignore holds | `lifecycle-git` |
| `git.nativeRefs` | Native | session | adapter pending | user deletes ignore holds | `lifecycle-git` |
| `git.repositoryHistory` | customer | repository | outside Native | owner outside Native | - |
| `plugins.installed` | customer | plugin | outside Native | owner outside Native | - |
| `components.caches` | Native | store | - | - | - |
| `skills.library` | Native | skill | adapter pending | user deletes ignore holds | `lifecycle-app-records` |
| `skills.installed` | external agent | skill | adapter pending | owner outside Native | `lifecycle-external-agents` |
| `skills.trash` | Native | skill | adapter pending | user deletes ignore holds | `lifecycle-app-records` |
| `icons.agents` | Native | store | adapter pending | - | `lifecycle-app-records` |
| `icons.projects` | Native | project | adapter pending | user deletes ignore holds | `lifecycle-app-records` |
| `celebrations.assets` | Native | store | adapter pending | - | `lifecycle-app-records` |
| `updates.app` | Native | store | - | - | - |
| `diagnostics.sentLog` | Native | store | adapter pending | pruned automatically, ignoring holds | `lifecycle-app-records` |
| `diagnostics.crashReportCache` | Native | store | adapter pending | pruned automatically, ignoring holds | `lifecycle-app-records` |
| `diagnostics.commandCoverage` | Native | store | adapter pending | pruned automatically, ignoring holds | `lifecycle-app-records` |
| `diagnostics.system` | operating system | store | outside Native | owner outside Native | - |
| `agents.histories` | external agent | session | adapter pending | owner outside Native | `lifecycle-external-agents` |
| `agents.configuration` | external agent | agent | outside Native | owner outside Native | - |
| `agents.credentials` | external agent | agent | outside Native | owner outside Native | - |
| `tools.credentials` | customer | store | outside Native | owner outside Native | - |
| `tools.packageCaches` | customer | store | outside Native | owner outside Native | - |
| `customer.backups` | customer | store | outside Native | owner outside Native | - |
| `customer.exports` | customer | store | outside Native | owner outside Native | - |

### `host.database`

The host's durable state: agents, sessions with their MCP configuration and settings, unfinished prompts and attachments, queued messages, approvals, activity, notifications, titles, tasks and closed-session choices.

- **Owner:** Native (verified in source). **Records:** session. **Holds:** user content, paths, commands, credentials, identifiers, configuration.
- **Copies:** primary `HostDir/host.sqlite`, SQLite (meta, agents, sessions, turns, queue, requests, approvals, activity, projects, plugin_choices, notifications, titles, tasks, closed_session_config); write-ahead log `HostDir/host.sqlite-wal`, SQLite; shared memory `HostDir/host.sqlite-shm`, SQLite.
- **Retention:** at host start, requests after 7 days and command activity after 30; the newest 200 notifications; tasks and other activity kept. **Today:** Forgetting a task deletes its session with its turns, queue, approvals and titles. Nothing vacuums or turns on secure delete, so freed pages and the log keep deleted rows for a while.
- **Export:** adapter pending. **Delete:** adapter pending. **Hold:** pruned automatically, ignoring holds.
- **Follow-up:** `lifecycle-host-database`. **Code:** `Packages/NativeHost/Sources/NativeHost/HostStore.swift`, `Packages/NativeHost/Sources/NativeHostProtocol/HostLocation.swift`.

### `host.runtime`

The host's socket and lock, the link socket, and a development host's launchd job.

- **Owner:** Native (verified in source). **Records:** host. **Holds:** paths.
- **Copies:** primary `HostDir/host.sock`, files; primary `HostDir/host.lock`, files; primary `HostDir/Link/link.sock`, files; primary `HostDir/launchd.plist`, property list.
- **Retention:** until replaced. **Today:** Made again each time the host starts.
- **Export:** -. **Delete:** -. **Hold:** -.
- **Follow-up:** none. **Code:** `Packages/NativeHost/Sources/NativeHostProtocol/HostLocation.swift`, `Packages/NativeHost/Sources/NativeHostClient/LaunchdSessionJob.swift`.

### `host.credentials`

Agent sign-in secrets the user gave Native, by agent and method.

- **Owner:** Native (verified in source). **Records:** agent. **Holds:** credentials, identifiers.
- **Copies:** primary Keychain service `Native Host`, Keychain items; primary `HostDir/credentials.json`, JSON.
- **Retention:** until the user removes it. **Today:** Removing a sign-in method deletes it. A release host at its standard location uses the Keychain; development, custom and portable hosts use a 0600 file.
- **Export:** -. **Delete:** adapter pending. **Hold:** user deletes ignore holds.
- **Follow-up:** `lifecycle-secrets`. **Code:** `Packages/NativeHost/Sources/NativeHost/HostCore+CredentialsStore.swift`.

### `host.pairingIdentity`

The host's link identity key and the devices paired with it, with their names and grants.

- **Owner:** Native (verified in source). **Records:** device. **Holds:** credentials, identifiers.
- **Copies:** primary `HostDir/Link/identity.key`, files; primary `HostDir/Link/devices.json`, JSON.
- **Retention:** until the user removes it. **Today:** Revoking a device marks it revoked and keeps its entry.
- **Export:** -. **Delete:** adapter pending. **Hold:** user deletes ignore holds.
- **Follow-up:** `lifecycle-secrets`. **Code:** `Packages/NativeLink/Sources/NativeLink/Identity/LinkKeyStore.swift`, `Packages/NativeLink/Sources/NativeLink/Host/LinkDevice.swift`.

### `orchestration.tokenSecret`

The secret that signs orchestration MCP session tokens, and the port the server last used, kept by the host and by the app.

- **Owner:** Native (verified in source). **Records:** host. **Holds:** credentials.
- **Copies:** primary `HostDir/MCP/token-secret`, files; primary `HostDir/MCP/port`, files; primary `AppSupport/Orchestration/<channel>/token-secret`, files; primary `AppSupport/Orchestration/<channel>/port`, files.
- **Retention:** until replaced. **Today:** Replaced or forgotten by its owner, which ends every session token it signed.
- **Export:** -. **Delete:** adapter pending. **Hold:** -.
- **Follow-up:** `lifecycle-secrets`. **Code:** `Packages/MCPServer/Sources/MCP/MCPServerStore.swift`, `Packages/NativeHost/Sources/NativeHost/HostTasks.swift`, `native/Orchestration/OrchestrationPlugin.swift`.

### `host.updates`

A standalone host's installed builds, the build being staged and the update ledger.

- **Owner:** Native (verified in source). **Records:** host. **Holds:** configuration.
- **Copies:** primary `~/.native/host/versions/<build>`, files; primary `~/.native/host/native-host`, files; primary `~/.native/host/native-host.next`, files; primary `~/.native/host/update-ledger.json`, JSON.
- **Retention:** the current and previous builds. **Today:** Confirming an update removes builds older than the previous one.
- **Export:** -. **Delete:** -. **Hold:** -.
- **Follow-up:** none. **Code:** `Packages/HostUpdater/Sources/HostUpdater/HostBinaryInstaller.swift`, `Packages/NativeHost/Sources/NativeHostMac/MacHostUpdates.swift`.

### `remote.hostCopies`

What a paired host keeps for the tasks it runs (its own host database, worktrees and agent histories), on that machine.

- **Owner:** Native (verified in source). **Records:** session. **Holds:** user content, paths, commands, credentials, identifiers.
- **Copies:** primary <paired host>: that host's own stores, reached only through its host, owner-defined.
- **Retention:** that host's own rules. **Today:** Unpairing forgets the host here; everything it keeps stays on that machine.
- **Export:** adapter pending. **Delete:** adapter pending. **Hold:** pruned automatically, ignoring holds.
- **Follow-up:** `lifecycle-remote-hosts`. **Code:** `native/Hosts/Model/RemoteHosts.swift`, `Packages/NativeLink/Sources/NativeLink/Device/FilePairedHostStore.swift`.

### `audit.approvals`

Approval requests and decisions with the device that decided, reserved for the approval audit.

- **Owner:** Native (unknown: enterprise-approval-audit hasn't merged; its schema, location and retention are unknown). **Records:** approval. **Holds:** identifiers, audit.
- **Copies:** primary location not determined, owner-defined.
- **Retention:** not determined. **Today:** Not stored yet: a decision lives only in the host's in-memory replay.
- **Export:** adapter pending. **Delete:** adapter pending. **Hold:** not determined.
- **Follow-up:** `lifecycle-host-database`. **Code:** `Packages/NativeHost/Sources/NativeHost/`.

### `app.sessionCatalog`

The task list as agents last reported it: session ids, titles, folders and times.

- **Owner:** Native (verified in source). **Records:** session. **Holds:** user content, paths, identifiers.
- **Copies:** primary `AppSupport/session-catalog.json`, JSON.
- **Retention:** until replaced. **Today:** Rewritten when agents list their sessions again.
- **Export:** adapter pending. **Delete:** adapter pending. **Hold:** user deletes ignore holds. **Tombstones:** reimported from `agents.histories`.
- **Follow-up:** `lifecycle-app-records`. **Code:** `native/Models/SessionCatalog.swift`.

### `app.drafts`

Unsent prompts: new-task drafts, composer drafts and the held draft.

- **Owner:** Native (verified in source). **Records:** session. **Holds:** user content, paths.
- **Copies:** primary defaults `unsentSessions`, `composerDrafts`, `compose.heldDraft`, defaults.
- **Retention:** until the user removes it. **Today:** Removed when sent or discarded.
- **Export:** adapter pending. **Delete:** adapter pending. **Hold:** user deletes ignore holds.
- **Follow-up:** `lifecycle-app-records`. **Code:** `native/Models/UnsentSessions.swift`, `native/Models/ComposerDrafts.swift`.

### `app.sessionState`

What the app remembers per task: titles, chosen settings and modes, the archived, deleted, pinned, unread and order lists, turn baselines and pull request questions.

- **Owner:** Native (verified in source). **Records:** session. **Holds:** user content, paths, identifiers, configuration.
- **Copies:** primary defaults `sessionTitles.*`, `sessionConfigChoices`, `sessionModes`, `archivedSessions`, `deletedSessions`, `pinnedSessions`, `unreadSessions`, `sessionOrder`, `taskSessions`, `earlierConversations`, `orchestrationTasks`, `git.turnBaselines`, `pullRequestQuestions`, defaults.
- **Retention:** the newest 200 turn baselines and pull request questions; the rest unbounded. **Today:** Archiving keeps a task's entries and deleting one marks it deleted; only the two bounded lists drop old entries.
- **Export:** adapter pending. **Delete:** adapter pending. **Hold:** pruned automatically, ignoring holds.
- **Follow-up:** `lifecycle-app-records`. **Code:** `native/Plugins/SessionTitles.swift`, `native/Models/ArchivedSessions.swift`, `native/Models/DeletedSessions.swift`, `native/Modes/Model/ModeLibrary.swift`, `native/Git/Model/GitTurnBaselines.swift`.

### `app.projects`

Projects and their settings: folders, archived projects, agent and model defaults, actions, AI instructions, custom modes and search exclusions.

- **Owner:** Native (verified in source). **Records:** project. **Holds:** user content, paths, commands, configuration.
- **Copies:** primary defaults `projects`, `archivedProjects`, `projectDefaults.<project>.*`, `projectActions.*`, `aiInstructions.*`, `modes.custom`, `search.excludedFolders`, defaults.
- **Retention:** until the user removes it. **Today:** Kept until the user removes the project or changes the setting.
- **Export:** adapter pending. **Delete:** adapter pending. **Hold:** user deletes ignore holds.
- **Follow-up:** `lifecycle-app-records`. **Code:** `native/Models/Projects.swift`, `native/ProjectActions/Model/ProjectActionStore.swift`, `native/AIInstructions/Model/AIInstructionsStore.swift`.

### `app.repositoryTrust`

Task scripts, and whether each project runs the scripts its repository commits.

- **Owner:** Native (verified in source). **Records:** project. **Holds:** paths, commands, configuration.
- **Copies:** primary defaults `taskScripts.configuration`, `git.setupScripts`, defaults.
- **Retention:** until the user removes it. **Today:** Kept until the user changes it.
- **Export:** adapter pending. **Delete:** adapter pending. **Hold:** user deletes ignore holds.
- **Follow-up:** `lifecycle-app-records`. **Code:** `native/TaskScripts/Model/TaskScriptSettings.swift`.

### `app.settings`

Other preferences that can name people, folders or hosts: agent defaults, terminal, GitHub accounts, host looks, seen-notification cursors and telemetry ids.

- **Owner:** Native (verified in source). **Records:** store. **Holds:** paths, identifiers, configuration.
- **Copies:** primary defaults `agentDefaults.<agent>.*`, `terminal.*`, `github.*`, `hostLooks`, `NativeHostSeenNotifications`, `NativeHostSeenActivity`, `telemetry.*`, defaults.
- **Retention:** until the user removes it. **Today:** Kept until changed.
- **Export:** adapter pending. **Delete:** adapter pending. **Hold:** user deletes ignore holds.
- **Follow-up:** `lifecycle-app-records`. **Code:** `native/Models/AgentSessionDefaults.swift`, `native/Telemetry/TelemetryCenter.swift`.

### `app.usage`

Usage limits with their scheduled resumes, including the prompt a limit stopped, and daily activity by project and task.

- **Owner:** Native (verified in source). **Records:** session. **Holds:** user content, paths, identifiers.
- **Copies:** primary `AppSupport/usage-limits.json`, JSON; primary `AppSupport/usage-activity.json`, JSON.
- **Retention:** activity for 400 days. **Today:** Activity older than 400 days drops; a scheduled resume goes when it runs or is cancelled.
- **Export:** adapter pending. **Delete:** adapter pending. **Hold:** pruned automatically, ignoring holds.
- **Follow-up:** `lifecycle-app-records`. **Code:** `native/Usage/Core/UsageLimitsStore.swift`, `native/Usage/Core/ActivityStore.swift`.

### `app.policyEnrollment`

The restricted mode the organization last deployed, and its policy revision.

- **Owner:** Native (verified in source). **Records:** store. **Holds:** configuration.
- **Copies:** primary `AppSupport/Policy/enrollment.json`, JSON.
- **Retention:** until the organization deploys ordinary mode. **Today:** Removed only when managed policy returns to ordinary mode; removing it otherwise would weaken a restricted deployment.
- **Export:** -. **Delete:** -. **Hold:** -.
- **Follow-up:** none. **Code:** `native/Policy/PolicyCenter.swift`, `Packages/NativePolicy/Sources/NativePolicy/PolicyEnrollment.swift`.

### `mcp.servers`

MCP servers the user added: commands, URLs, switches and remembered script approvals.

- **Owner:** Native (verified in source). **Records:** store. **Holds:** paths, commands, credential references, configuration.
- **Copies:** primary `AppSupport/mcp-servers.json`, JSON.
- **Retention:** until the user removes it. **Today:** Removing a server forgets it and its approvals.
- **Export:** adapter pending. **Delete:** adapter pending. **Hold:** user deletes ignore holds.
- **Follow-up:** `lifecycle-app-records`. **Code:** `native/MCP/Model/MCPLibrary.swift`, `native/MCP/Model/MCPStoreFile.swift`.

### `mcp.secrets`

The secret fields of the user's MCP servers, one item per server.

- **Owner:** Native (verified in source). **Records:** store. **Holds:** credentials.
- **Copies:** primary Keychain service `Native MCP servers`, Keychain items.
- **Retention:** until the user removes it. **Today:** Removing a server clears its item.
- **Export:** -. **Delete:** adapter pending. **Hold:** user deletes ignore holds.
- **Follow-up:** `lifecycle-secrets`. **Code:** `Packages/MCPClient/Sources/MCPClient/Managed/SecretStore.swift`.

### `pairing.hosts`

Hosts this Mac paired with (addresses, SSH destination and a per-host device key), and the installation secret that tags this Mac.

- **Owner:** Native (verified in source). **Records:** host. **Holds:** credentials, identifiers.
- **Copies:** primary `AppSupport/Hosts/<host>.json`, JSON; primary defaults `RemoteHostsInstallationSecret`, defaults.
- **Retention:** until the user removes it. **Today:** Unpairing removes the host's file; the installation secret stays.
- **Export:** -. **Delete:** adapter pending. **Hold:** user deletes ignore holds.
- **Follow-up:** `lifecycle-secrets`. **Code:** `Packages/NativeLink/Sources/NativeLink/Device/FilePairedHostStore.swift`, `native/Hosts/Model/RemoteHosts.swift`.

### `pairing.companion`

The companion app's paired hosts, active host, per-host preferences and installation secret.

- **Owner:** Native (verified in source). **Records:** host. **Holds:** credentials, identifiers.
- **Copies:** primary Keychain service `native.companion.paired-hosts`, Keychain items; primary defaults `installationSecret`, `activeHost`, `host.<host>.preferences`, defaults.
- **Retention:** until the user removes it. **Today:** Forgetting a host removes its item and preferences.
- **Export:** -. **Delete:** adapter pending. **Hold:** user deletes ignore holds.
- **Follow-up:** `lifecycle-secrets`. **Code:** `Companion/NativeCompanion/Model/CompanionDevice.swift`.

### `search.index`

Searchable copies of transcripts: titles, folders, message text, and how far each agent history file has been read.

- **Owner:** Native (verified in source). **Records:** session. **Holds:** user content, paths, commands.
- **Copies:** primary `AppSupport/search-index.sqlite`, SQLite (sessions, items, items_fts, sources, meta); write-ahead log `AppSupport/search-index.sqlite-wal`, SQLite; shared memory `AppSupport/search-index.sqlite-shm`, SQLite.
- **Retention:** `policy.search.retentionDays`. **Today:** Retention deletes sessions last active before the cutoff (one without a time counts as oldest) but keeps their `sources` rows and doesn't vacuum. Excluding a folder removes its sessions; clearing the index drops and vacuums it.
- **Export:** adapter pending. **Delete:** adapter pending. **Hold:** pruned automatically, ignoring holds. **Tombstones:** reimported from `agents.histories`, `app.sessionCatalog`.
- **Follow-up:** `lifecycle-search`. **Code:** `Packages/Search/Sources/Search/SearchStore.swift`, `native/Search/TranscriptSearchBackfill.swift`.

### `automation.store`

Goals, automations and workflows with their runs and the tasks they started: objectives, prompts, outputs and folders.

- **Owner:** Native (verified in source). **Records:** automation. **Holds:** user content, paths, identifiers.
- **Copies:** primary `AppSupport/goals.json`, JSON; primary `<automationDataDirectory>/goals.json` when the `automationDataDirectory` default moves it, JSON; primary `AppSupport/automations.json`, JSON; primary `<automationDataDirectory>/automations.json` when the `automationDataDirectory` default moves it, JSON; primary `AppSupport/workflow-runs.json`, JSON; primary `<automationDataDirectory>/workflow-runs.json` when the `automationDataDirectory` default moves it, JSON; primary `AppSupport/workflow-tasks.json`, JSON; primary `<automationDataDirectory>/workflow-tasks.json` when the `automationDataDirectory` default moves it, JSON.
- **Retention:** 50 runs per automation, 100 workflow runs, step-task records cut to 500 past 1,000; goals unbounded. **Today:** Old runs drop past those limits; deleting an automation or a goal removes it.
- **Export:** adapter pending. **Delete:** adapter pending. **Hold:** pruned automatically, ignoring holds.
- **Follow-up:** `lifecycle-automation`. **Code:** `Packages/Automation/Sources/NativeAutomation/AutomationStorage.swift`, `native/Automation/Integration/StepTaskRecords.swift`.

### `expeditions.store`

Expeditions and the tasks their crews ran.

- **Owner:** Native (verified in source). **Records:** expedition. **Holds:** user content, paths, identifiers.
- **Copies:** primary `AppSupport/expeditions.json`, JSON; primary `<automationDataDirectory>/expeditions.json` when the `automationDataDirectory` default moves it, JSON; primary `AppSupport/expedition-tasks.json`, JSON; primary `<automationDataDirectory>/expedition-tasks.json` when the `automationDataDirectory` default moves it, JSON.
- **Retention:** until the user removes it. **Today:** No limit; nothing prunes them.
- **Export:** adapter pending. **Delete:** adapter pending. **Hold:** user deletes ignore holds.
- **Follow-up:** `lifecycle-automation`. **Code:** `Packages/Automation/Sources/NativeAutomation/AutomationStorage.swift`, `native/Expeditions/Integration/ExpeditionCrewRecords.swift`.

### `expeditions.documents`

Each expedition's logbook, route, debrief, reports and checkpoints.

- **Owner:** Native (verified in source). **Records:** expedition. **Holds:** user content.
- **Copies:** primary `~/.native/expeditions/<expedition>`, files.
- **Retention:** until the user removes it. **Today:** Nothing deletes them; checkpoints are written read-only.
- **Export:** adapter pending. **Delete:** adapter pending. **Hold:** user deletes ignore holds.
- **Follow-up:** `lifecycle-automation`. **Code:** `Packages/Expeditions/Sources/NativeExpeditions/ExpeditionDocuments.swift`.

### `temp.attachments`

Pasted images and pull request task briefs written for an agent to read.

- **Owner:** Native (verified in source). **Records:** session. **Holds:** user content.
- **Copies:** temporary `$TMPDIR/Native Attachments/<attachment>`, files.
- **Retention:** until the system clears temporary files. **Today:** Native never removes them.
- **Export:** adapter pending. **Delete:** adapter pending. **Hold:** user deletes ignore holds.
- **Follow-up:** `lifecycle-app-records`. **Code:** `Packages/ACP/Sources/ACP/Prompt/PromptAttachment+Loading.swift`, `native/PullRequestTasks/Model/PullRequestTaskCheckout.swift`.

### `temp.workingFiles`

Short-lived working files: artifact previews, terminal configuration, sign-in status, skill staging and terminal resource links.

- **Owner:** Native (verified in source). **Records:** store. **Holds:** user content, configuration.
- **Copies:** temporary `$TMPDIR/Native-Artifact-<id>`, files; temporary `$TMPDIR/native-terminal-<id>`, files; temporary `$TMPDIR/native-sign-in-<id>.status`, files; temporary `$TMPDIR/native-skills-<id>`, files; temporary `Caches/ghostty-resources`, files.
- **Retention:** removed by the code that made them. **Today:** Previews close with their viewer, terminal configuration goes right after use, sign-in status when sign-in ends and skill staging on install or discard; terminal links are rebuilt at launch.
- **Export:** adapter pending. **Delete:** adapter pending. **Hold:** pruned automatically, ignoring holds.
- **Follow-up:** `lifecycle-app-records`. **Code:** `Packages/ACP/Sources/ACP/Artifacts/ArtifactPreviewFile.swift`, `native/Terminal/Engine/GhosttyConfigBuilder.swift`, `native/AgentCatalog/AgentTerminalSignInRun.swift`, `Packages/Skills/Sources/Skills/Files/SkillFileSystem.swift`.

### `github.pullRequestQuestions`

Pull request context written for questions about it: its description and diffs.

- **Owner:** Native (verified in source). **Records:** pullRequest. **Holds:** user content, paths.
- **Copies:** primary `AppSupport/PullRequestQuestions/<host>/<owner>/<name>-<number>`, files.
- **Retention:** kept indefinitely. **Today:** Diffs are replaced when the context is written again; folders are never removed.
- **Export:** adapter pending. **Delete:** adapter pending. **Hold:** user deletes ignore holds.
- **Follow-up:** `lifecycle-app-records`. **Code:** `native/GitHub/Ask/Model/PullRequestAskCenter.swift`.

### `github.pullRequestClones`

Repositories cloned to start pull request tasks, in the clone folder (by default the user's developer folder). Native made them, but they are ordinary checkouts the user may work in, so their owner isn't established.

- **Owner:** unknown (verified in source). **Records:** repository. **Holds:** user content, paths.
- **Copies:** primary `<pullRequestTasks.cloneFolder>/<repository>` when the `pullRequestTasks.cloneFolder` default moves it, git worktree.
- **Retention:** until the user removes it. **Today:** Native never removes them.
- **Export:** outside Native. **Delete:** outside Native. **Hold:** owner outside Native.
- **Follow-up:** none. **Code:** `native/PullRequestTasks/Model/PullRequestTaskCheckout.swift`.

### `git.taskWorktrees`

Worktrees made for tasks, with everything the agent and the user changed in them.

- **Owner:** Native (verified in source). **Records:** session. **Holds:** user content, paths.
- **Copies:** primary `~/.native/worktrees/<repository>/<task>`, git worktree; primary `<gitWorktreesFolder>/<repository>/<task>` when the `gitWorktreesFolder` default moves it, git worktree.
- **Retention:** with its session. **Today:** Removing a task's worktree takes a checkpoint first; Git Cleanup moves leftover folders to the Trash.
- **Export:** adapter pending. **Delete:** adapter pending. **Hold:** user deletes ignore holds.
- **Follow-up:** `lifecycle-git`. **Code:** `native/Git/Model/GitStore+TaskWorkspaces.swift`, `native/Git/Cleanup/GitCleanupModel+Run.swift`.

### `git.nativeRefs`

Refs and config Native adds to repositories: task checkpoints, archived branches and worktrees, worktree bases and branch notes.

- **Owner:** Native (verified in source). **Records:** session. **Holds:** user content, paths.
- **Copies:** primary repository `refs/native-checkpoints/*`, `refs/native-archived-branches/*`, `refs/native/worktree-bases/*`, `nativeArchivedWorktree.*`, `nativeArchivedBranch.*`, `branch.*.native*`, git refs and config.
- **Retention:** checkpoints kept indefinitely; a worktree base until its fetch ends. **Today:** Restoring an archived branch deletes its ref; nothing deletes checkpoints.
- **Export:** adapter pending. **Delete:** adapter pending. **Hold:** user deletes ignore holds.
- **Follow-up:** `lifecycle-git`. **Code:** `Packages/Git/Sources/Git/Repository/Repository+Checkpoints.swift`, `Packages/Git/Sources/Git/Repository/Repository+TaskBranches.swift`, `Packages/Git/Sources/Git/Repository/Repository+ArchivedWorktrees.swift`, `Packages/Git/Sources/Git/Repository/Repository+WorktreeBase.swift`.

### `git.repositoryHistory`

Git objects and reflogs in the user's repositories that still hold snapshots Native made: turn baselines, removed checkpoints and task commits.

- **Owner:** customer (verified in source). **Records:** repository. **Holds:** user content.
- **Copies:** git objects <repository>: loose and packed objects, git objects; reflog <repository>: reflogs of the branches tasks used, git refs and config.
- **Retention:** owner decides. **Today:** Left to git gc and the repository's own settings.
- **Export:** outside Native. **Delete:** outside Native. **Hold:** owner outside Native.
- **Follow-up:** none. **Code:** `native/Git/Model/GitTurnBaselines.swift`.

### `plugins.installed`

Plugins the user installed from manifests, with their assets.

- **Owner:** customer (verified in source). **Records:** plugin. **Holds:** commands, configuration.
- **Copies:** primary `~/.native/plugins/<plugin>`, files; primary `<pluginsDirectory>/<plugin>` when the `pluginsDirectory` default moves it, files.
- **Retention:** until the user removes it. **Today:** The user adds and removes them.
- **Export:** outside Native. **Delete:** outside Native. **Hold:** owner outside Native.
- **Follow-up:** none. **Code:** `native/Plugins/PluginRegistry.swift`.

### `components.caches`

Verified component bytes, managed adapter installs and remote plugin asset blobs, each in a folder its caller chooses.

- **Owner:** Native (dormant: no production caller). **Records:** store. **Holds:** cache.
- **Copies:** primary location not determined, files.
- **Retention:** not determined. **Today:** Nothing constructs them in production yet.
- **Export:** -. **Delete:** -. **Hold:** -.
- **Follow-up:** none. **Code:** `Packages/HostUpdater/Sources/HostUpdater/PinnedComponentCache.swift`, `Packages/NativeHost/Sources/NativeHost/ManagedAdapterInstaller.swift`, `Packages/NativeHost/Sources/NativeHostClient/PluginAssets.swift`.

### `skills.library`

Which skills Native installed, from where, and their switches.

- **Owner:** Native (verified in source). **Records:** skill. **Holds:** paths, configuration.
- **Copies:** primary `AppSupport/skills.json`, JSON.
- **Retention:** until the user removes it. **Today:** Uninstalling a skill removes its entry.
- **Export:** adapter pending. **Delete:** adapter pending. **Hold:** user deletes ignore holds.
- **Follow-up:** `lifecycle-app-records`. **Code:** `native/Skills/Model/SkillLibrary.swift`.

### `skills.installed`

Skill files installed into agents' skill folders, for the user or for a project.

- **Owner:** external agent (verified in source). **Records:** skill. **Holds:** commands, configuration.
- **Copies:** primary <agent home>: each agent's user or project skill folder, files.
- **Retention:** until the user removes it. **Today:** Uninstalling moves the files to Skills Trash.
- **Export:** -. **Delete:** adapter pending. **Hold:** owner outside Native.
- **Follow-up:** `lifecycle-external-agents`. **Code:** `Packages/Skills/Sources/Skills/Install/SkillInstaller.swift`.

### `skills.trash`

Uninstalled skills, kept so the uninstall can be undone.

- **Owner:** Native (verified in source). **Records:** skill. **Holds:** commands, configuration.
- **Copies:** trash `AppSupport/Skills Trash/<entry>`, files.
- **Retention:** never emptied. **Today:** Nothing empties it.
- **Export:** adapter pending. **Delete:** adapter pending. **Hold:** user deletes ignore holds.
- **Follow-up:** `lifecycle-app-records`. **Code:** `native/Skills/Model/SkillLibrary.swift`.

### `icons.agents`

Agent icons and the registry index they came from.

- **Owner:** Native (verified in source). **Records:** store. **Holds:** cache.
- **Copies:** primary `AppSupport/AgentIcons/registry.json`, JSON; primary `AppSupport/AgentIcons/registry-<hash>.json`, JSON; primary `AppSupport/AgentIcons/icons/<icon>.svg`, files.
- **Retention:** index refreshed daily, icons weekly. **Today:** Replaced when refreshed; never pruned.
- **Export:** -. **Delete:** adapter pending. **Hold:** -.
- **Follow-up:** `lifecycle-app-records`. **Code:** `native/AgentIcons/AgentIconRegistry.swift`.

### `icons.projects`

Icons detected in or chosen for each project.

- **Owner:** Native (verified in source). **Records:** project. **Holds:** user content, cache.
- **Copies:** primary `AppSupport/ProjectIcons/<kind>-<project>.<format>`, files; primary defaults `projectIcons.choices`, defaults.
- **Retention:** with its project. **Today:** Replaced when detected again or changed; never pruned.
- **Export:** adapter pending. **Delete:** adapter pending. **Hold:** user deletes ignore holds.
- **Follow-up:** `lifecycle-app-records`. **Code:** `native/ProjectIcons/ProjectIconStore.swift`.

### `celebrations.assets`

Downloaded celebration artwork packs.

- **Owner:** Native (verified in source). **Records:** store. **Holds:** cache.
- **Copies:** primary `AppSupport/CelebrationAssets/<edition>`, files.
- **Retention:** until replaced. **Today:** Replaced by newer packs; never pruned.
- **Export:** -. **Delete:** adapter pending. **Hold:** -.
- **Follow-up:** `lifecycle-app-records`. **Code:** `native/Celebrations/CelebrationAssetStore.swift`.

### `updates.app`

Update downloads and installer state the update framework keeps.

- **Owner:** Native (verified in source). **Records:** store. **Holds:** cache.
- **Copies:** primary Caches: the update framework's own folders, owner-defined.
- **Retention:** the update framework's own. **Today:** Managed by the update framework.
- **Export:** -. **Delete:** -. **Hold:** -.
- **Follow-up:** none. **Code:** `native/Updates/SparkleUpdateDriver.swift`.

### `diagnostics.sentLog`

A readable log of the telemetry Native sent: event names, counts and versions.

- **Owner:** Native (verified in source). **Records:** store. **Holds:** identifiers, diagnostics.
- **Copies:** primary `AppSupport/Telemetry/sent.jsonl`, JSON Lines.
- **Retention:** the newest 200 entries. **Today:** Old entries drop; its clear action has no caller.
- **Export:** adapter pending. **Delete:** adapter pending. **Hold:** pruned automatically, ignoring holds.
- **Follow-up:** `lifecycle-app-records`. **Code:** `Packages/Telemetry/Sources/NativeTelemetry/TelemetrySentLog.swift`.

### `diagnostics.crashReportCache`

Error and crash reports waiting to send while diagnostics are on.

- **Owner:** Native (verified in source). **Records:** store. **Holds:** diagnostics.
- **Copies:** primary `Caches/SentryTelemetry`, files.
- **Retention:** until diagnostics turn off. **Today:** Turning diagnostics off removes the cache.
- **Export:** adapter pending. **Delete:** adapter pending. **Hold:** pruned automatically, ignoring holds.
- **Follow-up:** `lifecycle-app-records`. **Code:** `native/Telemetry/SentryTelemetry.swift`.

### `diagnostics.commandCoverage`

Counts of programs that approvals saw and command knowledge doesn't describe: program names only.

- **Owner:** Native (verified in source). **Records:** store. **Holds:** commands, diagnostics.
- **Copies:** primary `AppSupport/CommandKnowledge/unknown-programs.json`, JSON.
- **Retention:** up to 256 programs. **Today:** Clear Counts removes them, and policy can turn counting off.
- **Export:** adapter pending. **Delete:** adapter pending. **Hold:** pruned automatically, ignoring holds.
- **Follow-up:** `lifecycle-app-records`. **Code:** `native/CommandKnowledge/CommandKnowledgeCenter.swift`, `Packages/ApprovalAnalysis/Sources/ApprovalAnalysis/UnknownCommandCounts.swift`.

### `diagnostics.system`

What the operating system keeps from Native: unified log messages, crash reports and Notification Center history. A portable host's log goes to its supervisor.

- **Owner:** operating system (verified in source). **Records:** store. **Holds:** user content, paths, commands, diagnostics.
- **Copies:** primary OS: unified logging, crash reports, Notification Center, owner-defined.
- **Retention:** owner decides. **Today:** The system expires them on its own schedule.
- **Export:** outside Native. **Delete:** outside Native. **Hold:** owner outside Native.
- **Follow-up:** none. **Code:** `native/Usage/System/UserNotificationPoster.swift`, `Packages/NativeHost/Sources/NativeHostProtocol/Platform.swift`.

### `agents.histories`

Each agent's own conversation history, wherever the agent keeps it. Native reads it to load and search tasks.

- **Owner:** external agent (verified in source). **Records:** session. **Holds:** user content, paths, commands.
- **Copies:** primary <agent home>: the agent's own history files, owner-defined.
- **Retention:** owner decides. **Today:** Native never deletes them; an agent may offer its own way to.
- **Export:** adapter pending. **Delete:** adapter pending. **Hold:** owner outside Native.
- **Follow-up:** `lifecycle-external-agents`. **Code:** `Packages/Search/Sources/Search/History/`.

### `agents.configuration`

Agents' own settings and MCP and plugin configuration, which Native reads and changes only through the agent's command line.

- **Owner:** external agent (verified in source). **Records:** agent. **Holds:** paths, commands, configuration.
- **Copies:** primary <agent home>: the agent's configuration files, owner-defined.
- **Retention:** owner decides. **Today:** Changed only through the agent's own command line.
- **Export:** outside Native. **Delete:** outside Native. **Hold:** owner outside Native.
- **Follow-up:** none. **Code:** `native/AgentCatalog/`.

### `agents.credentials`

Agents' own sign-in. Native never reads it; it shows only the status an agent reports.

- **Owner:** external agent (verified in source). **Records:** agent. **Holds:** credentials.
- **Copies:** primary <agent home>: wherever the agent keeps its sign-in, owner-defined.
- **Retention:** owner decides. **Today:** Signing out belongs to the agent.
- **Export:** outside Native. **Delete:** outside Native. **Hold:** owner outside Native.
- **Follow-up:** none. **Code:** none.

### `tools.credentials`

Sign-in for tools Native runs: the GitHub command line, git credential helpers, SSH keys.

- **Owner:** customer (verified in source). **Records:** store. **Holds:** credentials.
- **Copies:** primary customer: each tool's own store, owner-defined.
- **Retention:** owner decides. **Today:** Native never reads or removes them.
- **Export:** outside Native. **Delete:** outside Native. **Hold:** owner outside Native.
- **Follow-up:** none. **Code:** none.

### `tools.packageCaches`

Package manager caches and global installs used to run agent adapters.

- **Owner:** customer (verified in source). **Records:** store. **Holds:** cache.
- **Copies:** primary customer: the package manager's cache and global installs, owner-defined.
- **Retention:** owner decides. **Today:** Managed by the package manager.
- **Export:** outside Native. **Delete:** outside Native. **Hold:** owner outside Native.
- **Follow-up:** none. **Code:** `Packages/ACP/Sources/ACP/NpxLaunch.swift`.

### `customer.backups`

Copies beyond Native's reach: Time Machine and other backups, file system snapshots, the Trash, synced folders, and git remotes and forks.

- **Owner:** customer (verified in source). **Records:** store. **Holds:** user content, paths, commands, credentials.
- **Copies:** primary customer: backups, snapshots, the Trash, sync services, git remotes, owner-defined.
- **Retention:** owner decides. **Today:** Native can't see or remove them; every deletion result lists them.
- **Export:** outside Native. **Delete:** outside Native. **Hold:** owner outside Native.
- **Follow-up:** none. **Code:** none.

### `customer.exports`

What the user took out of Native: exported patches and transcripts, copied text, files opened in other apps, and terminal history and output.

- **Owner:** customer (verified in source). **Records:** store. **Holds:** user content, paths, commands.
- **Copies:** primary customer: wherever the user saved or pasted it, owner-defined.
- **Retention:** owner decides. **Today:** Belongs to the user once exported.
- **Export:** outside Native. **Delete:** outside Native. **Hold:** owner outside Native.
- **Follow-up:** none. **Code:** `native/Platform/PlatformArtifactActions.swift`.
<!-- inventory:end -->
