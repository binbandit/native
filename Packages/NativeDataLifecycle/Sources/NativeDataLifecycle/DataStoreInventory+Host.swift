extension DataStoreInventory {
    /// The background host's stores, on this Mac and on paired hosts, and the approval audit it will keep.
    static let hostEntries: [DataStoreEntry] = [
        DataStoreEntry(
            .hostDatabase,
            "The host's durable state: agents, sessions with their MCP configuration and settings, unfinished"
                + " prompts and attachments, queued messages, approvals, activity, notifications, titles, tasks and"
                + " closed-session choices.",
            owners: [
                "Packages/NativeHost/Sources/NativeHost/HostStore.swift",
                "Packages/NativeHost/Sources/NativeHostProtocol/HostLocation.swift",
            ],
            ownership: .native,
            content: [.userContent, .paths, .commands, .credentials, .identifiers, .configuration], records: .session,
            copies: [
                DataCopySpec(
                    .primary, .file(.hostData, ["host.sqlite"]),
                    .sqlite(tables: [
                        "meta", "agents", "sessions", "turns", "queue", "requests", "approvals", "activity", "projects",
                        "plugin_choices", "notifications", "titles", "tasks", "closed_session_config",
                    ])),
                DataCopySpec(.writeAheadLog, .file(.hostData, ["host.sqlite-wal"]), .sqlite(tables: [])),
                DataCopySpec(.sharedMemory, .file(.hostData, ["host.sqlite-shm"]), .sqlite(tables: [])),
            ],
            retention: .ownerRule(
                "at host start, requests after 7 days and command activity after 30; the newest 200 notifications;"
                    + " tasks and other activity kept"),
            today: "Forgetting a task deletes its session with its turns, queue, approvals and titles. Nothing vacuums"
                + " or turns on secure delete, so freed pages and the log keep deleted rows for a while.",
            support: .pendingPruned, followUp: .hostDatabase),
        DataStoreEntry(
            .hostRuntime, "The host's socket and lock, the link socket, and a development host's launchd job.",
            owners: [
                "Packages/NativeHost/Sources/NativeHostProtocol/HostLocation.swift",
                "Packages/NativeHost/Sources/NativeHostClient/LaunchdSessionJob.swift",
            ],
            ownership: .native, content: [.paths], records: .host,
            copies: [
                DataCopySpec(.primary, .file(.hostData, ["host.sock"]), .files),
                DataCopySpec(.primary, .file(.hostData, ["host.lock"]), .files),
                DataCopySpec(.primary, .file(.hostData, ["Link", "link.sock"]), .files),
                DataCopySpec(.primary, .file(.hostData, ["launchd.plist"]), .propertyList),
            ],
            retention: .untilReplaced, today: "Made again each time the host starts.", support: .none, followUp: nil),
        DataStoreEntry(
            .hostCredentials, "Agent sign-in secrets the user gave Native, by agent and method.",
            owners: ["Packages/NativeHost/Sources/NativeHost/HostCore+CredentialsStore.swift"],
            ownership: .native, content: [.credentials, .identifiers], records: .agent,
            copies: [
                DataCopySpec(.primary, .keychain(service: "Native Host"), .keychain),
                DataCopySpec(.primary, .file(.hostData, ["credentials.json"]), .json),
            ],
            retention: .userManaged,
            today: "Removing a sign-in method deletes it. A release host at its standard location uses the Keychain;"
                + " development, custom and portable hosts use a 0600 file.",
            support: DataSupport(export: .notApplicable, delete: .adapterPending, hold: .userActionsIgnoreHolds),
            followUp: .secrets),
        DataStoreEntry(
            .hostPairingIdentity,
            "The host's link identity key and the devices paired with it, with their names and grants.",
            owners: [
                "Packages/NativeLink/Sources/NativeLink/Identity/LinkKeyStore.swift",
                "Packages/NativeLink/Sources/NativeLink/Host/LinkDevice.swift",
            ],
            ownership: .native, content: [.credentials, .identifiers], records: .device,
            copies: [
                DataCopySpec(.primary, .file(.hostData, ["Link", "identity.key"]), .files),
                DataCopySpec(.primary, .file(.hostData, ["Link", "devices.json"]), .json),
            ],
            retention: .userManaged, today: "Revoking a device marks it revoked and keeps its entry.",
            support: DataSupport(export: .notApplicable, delete: .adapterPending, hold: .userActionsIgnoreHolds),
            followUp: .secrets),
        DataStoreEntry(
            .orchestrationTokenSecret,
            "The secret that signs orchestration MCP session tokens, and the port the server last used, kept by the"
                + " host and by the app.",
            owners: [
                "Packages/MCPServer/Sources/MCP/MCPServerStore.swift",
                "Packages/NativeHost/Sources/NativeHost/HostTasks.swift",
                "native/Orchestration/OrchestrationPlugin.swift",
            ],
            ownership: .native, content: [.credentials], records: .host,
            copies: [
                DataCopySpec(.primary, .file(.hostData, ["MCP", "token-secret"]), .files),
                DataCopySpec(.primary, .file(.hostData, ["MCP", "port"]), .files),
                DataCopySpec(.primary, .file(.appSupport, ["Orchestration", "<channel>", "token-secret"]), .files),
                DataCopySpec(.primary, .file(.appSupport, ["Orchestration", "<channel>", "port"]), .files),
            ],
            retention: .untilReplaced,
            today: "Replaced or forgotten by its owner, which ends every session token it signed.",
            support: DataSupport(export: .notApplicable, delete: .adapterPending, hold: .notApplicable),
            followUp: .secrets),
        DataStoreEntry(
            .hostUpdates, "A standalone host's installed builds, the build being staged and the update ledger.",
            owners: [
                "Packages/HostUpdater/Sources/HostUpdater/HostBinaryInstaller.swift",
                "Packages/NativeHost/Sources/NativeHostMac/MacHostUpdates.swift",
            ],
            ownership: .native, content: [.configuration], records: .host,
            copies: [
                DataCopySpec(.primary, .file(.nativeHome, ["host", "versions", "<build>"]), .files),
                DataCopySpec(.primary, .file(.nativeHome, ["host", "native-host"]), .files),
                DataCopySpec(.primary, .file(.nativeHome, ["host", "native-host.next"]), .files),
                DataCopySpec(.primary, .file(.nativeHome, ["host", "update-ledger.json"]), .json),
            ],
            retention: .ownerRule("the current and previous builds"),
            today: "Confirming an update removes builds older than the previous one.", support: .none, followUp: nil),
        DataStoreEntry(
            .remoteHostCopies,
            "What a paired host keeps for the tasks it runs (its own host database, worktrees and agent histories),"
                + " on that machine.",
            owners: [
                "native/Hosts/Model/RemoteHosts.swift",
                "Packages/NativeLink/Sources/NativeLink/Device/FilePairedHostStore.swift",
            ],
            ownership: .native, content: [.userContent, .paths, .commands, .credentials, .identifiers],
            records: .session,
            copies: [
                DataCopySpec(
                    .primary, .elsewhere(.pairedHost, "that host's own stores, reached only through its host"),
                    .ownerDefined)
            ],
            retention: .ownerRule("that host's own rules"),
            today: "Unpairing forgets the host here; everything it keeps stays on that machine.",
            support: .pendingPruned, followUp: .remoteHosts),
        DataStoreEntry(
            .approvalAudit,
            "Approval requests and decisions with the device that decided, reserved for the approval audit.",
            owners: ["Packages/NativeHost/Sources/NativeHost/"], ownership: .native,
            integration: .unknown(
                "enterprise-approval-audit hasn't merged; its schema, location and retention are unknown"),
            content: [.audit, .identifiers], records: .approval,
            copies: [DataCopySpec(.primary, .undetermined, .ownerDefined)], retention: .undetermined,
            today: "Not stored yet: a decision lives only in the host's in-memory replay.",
            support: DataSupport(export: .adapterPending, delete: .adapterPending, hold: .undetermined),
            followUp: .hostDatabase),
    ]
}
