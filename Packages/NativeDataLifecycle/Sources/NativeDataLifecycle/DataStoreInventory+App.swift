extension DataStoreInventory {
    /// The app's own records: tasks, drafts, projects, settings, pairings, search and automation.
    static let appEntries: [DataStoreEntry] = [
        DataStoreEntry(
            .sessionCatalog, "The task list as agents last reported it: session ids, titles, folders and times.",
            owners: ["native/Models/SessionCatalog.swift"], ownership: .native,
            content: [.userContent, .paths, .identifiers], records: .session,
            copies: [DataCopySpec(.primary, .file(.appSupport, ["session-catalog.json"]), .json)],
            retention: .untilReplaced, today: "Rewritten when agents list their sessions again.", support: .pending,
            reimportedFrom: [.agentHistories], followUp: .appRecords),
        DataStoreEntry(
            .drafts, "Unsent prompts: new-task drafts, composer drafts and the held draft.",
            owners: ["native/Models/UnsentSessions.swift", "native/Models/ComposerDrafts.swift"], ownership: .native,
            content: [.userContent, .paths], records: .session,
            copies: [
                DataCopySpec(.primary, .defaults(["unsentSessions", "composerDrafts", "compose.heldDraft"]), .defaults)
            ],
            retention: .userManaged, today: "Removed when sent or discarded.", support: .pending, followUp: .appRecords),
        DataStoreEntry(
            .sessionState,
            "What the app remembers per task: titles, chosen settings and modes, the archived, deleted, pinned, unread"
                + " and order lists, turn baselines and pull request questions.",
            owners: [
                "native/Plugins/SessionTitles.swift", "native/Models/ArchivedSessions.swift",
                "native/Models/DeletedSessions.swift", "native/Modes/Model/ModeLibrary.swift",
                "native/Git/Model/GitTurnBaselines.swift",
            ],
            ownership: .native, content: [.userContent, .paths, .identifiers, .configuration], records: .session,
            copies: [
                DataCopySpec(
                    .primary,
                    .defaults([
                        "sessionTitles.*", "sessionConfigChoices", "sessionModes", "archivedSessions",
                        "deletedSessions",
                        "pinnedSessions", "unreadSessions", "sessionOrder", "taskSessions", "earlierConversations",
                        "orchestrationTasks", "git.turnBaselines", "pullRequestQuestions",
                    ]), .defaults)
            ],
            retention: .ownerRule("the newest 200 turn baselines and pull request questions; the rest unbounded"),
            today: "Archiving keeps a task's entries and deleting one marks it deleted; only the two bounded lists"
                + " drop old entries.",
            support: .pendingPruned, followUp: .appRecords),
        DataStoreEntry(
            .projects,
            "Projects and their settings: folders, archived projects, agent and model defaults, actions, AI"
                + " instructions, custom modes and search exclusions.",
            owners: [
                "native/Models/Projects.swift", "native/ProjectActions/Model/ProjectActionStore.swift",
                "native/AIInstructions/Model/AIInstructionsStore.swift",
            ],
            ownership: .native, content: [.userContent, .paths, .commands, .configuration], records: .project,
            copies: [
                DataCopySpec(
                    .primary,
                    .defaults([
                        "projects", "archivedProjects", "projectDefaults.<project>.*", "projectActions.*",
                        "aiInstructions.*", "modes.custom", "search.excludedFolders",
                    ]), .defaults)
            ],
            retention: .userManaged, today: "Kept until the user removes the project or changes the setting.",
            support: .pending, followUp: .appRecords),
        DataStoreEntry(
            .repositoryTrust,
            "Task scripts, and whether each project runs the scripts its repository commits.",
            owners: ["native/TaskScripts/Model/TaskScriptSettings.swift"], ownership: .native,
            content: [.commands, .paths, .configuration], records: .project,
            copies: [DataCopySpec(.primary, .defaults(["taskScripts.configuration", "git.setupScripts"]), .defaults)],
            retention: .userManaged, today: "Kept until the user changes it.", support: .pending,
            followUp: .appRecords),
        DataStoreEntry(
            .settings,
            "Other preferences that can name people, folders or hosts: agent defaults, terminal, GitHub accounts,"
                + " host looks, seen-notification cursors and telemetry ids.",
            owners: ["native/Models/AgentSessionDefaults.swift", "native/Telemetry/TelemetryCenter.swift"],
            ownership: .native, content: [.identifiers, .paths, .configuration], records: .store,
            copies: [
                DataCopySpec(
                    .primary,
                    .defaults([
                        "agentDefaults.<agent>.*", "terminal.*", "github.*", "hostLooks", "NativeHostSeenNotifications",
                        "NativeHostSeenActivity", "telemetry.*",
                    ]), .defaults)
            ],
            retention: .userManaged, today: "Kept until changed.", support: .pending, followUp: .appRecords),
        DataStoreEntry(
            .usage,
            "Usage limits with their scheduled resumes, including the prompt a limit stopped, and daily activity"
                + " by project and task.",
            owners: ["native/Usage/Core/UsageLimitsStore.swift", "native/Usage/Core/ActivityStore.swift"],
            ownership: .native, content: [.userContent, .paths, .identifiers], records: .session,
            copies: [
                DataCopySpec(.primary, .file(.appSupport, ["usage-limits.json"]), .json),
                DataCopySpec(.primary, .file(.appSupport, ["usage-activity.json"]), .json),
            ],
            retention: .ownerRule("activity for 400 days"),
            today: "Activity older than 400 days drops; a scheduled resume goes when it runs or is cancelled.",
            support: .pendingPruned, followUp: .appRecords),
        DataStoreEntry(
            .policyEnrollment, "The restricted mode the organization last deployed, and its policy revision.",
            owners: [
                "native/Policy/PolicyCenter.swift", "Packages/NativePolicy/Sources/NativePolicy/PolicyEnrollment.swift",
            ],
            ownership: .native, content: [.configuration], records: .store,
            copies: [DataCopySpec(.primary, .file(.appSupport, ["Policy", "enrollment.json"]), .json)],
            retention: .ownerRule("until the organization deploys ordinary mode"),
            today: "Removed only when managed policy returns to ordinary mode; removing it otherwise would weaken a"
                + " restricted deployment.",
            support: .none, followUp: nil),
        DataStoreEntry(
            .mcpServers, "MCP servers the user added: commands, URLs, switches and remembered script approvals.",
            owners: ["native/MCP/Model/MCPLibrary.swift", "native/MCP/Model/MCPStoreFile.swift"], ownership: .native,
            content: [.commands, .paths, .configuration, .credentialReferences], records: .store,
            copies: [DataCopySpec(.primary, .file(.appSupport, ["mcp-servers.json"]), .json)],
            retention: .userManaged, today: "Removing a server forgets it and its approvals.", support: .pending,
            followUp: .appRecords),
        DataStoreEntry(
            .mcpSecrets, "The secret fields of the user's MCP servers, one item per server.",
            owners: ["Packages/MCPClient/Sources/MCPClient/Managed/SecretStore.swift"], ownership: .native,
            content: [.credentials], records: .store,
            copies: [DataCopySpec(.primary, .keychain(service: "Native MCP servers"), .keychain)],
            retention: .userManaged, today: "Removing a server clears its item.",
            support: DataSupport(export: .notApplicable, delete: .adapterPending, hold: .userActionsIgnoreHolds),
            followUp: .secrets),
        DataStoreEntry(
            .hostPairings,
            "Hosts this Mac paired with (addresses, SSH destination and a per-host device key), and the installation"
                + " secret that tags this Mac.",
            owners: [
                "Packages/NativeLink/Sources/NativeLink/Device/FilePairedHostStore.swift",
                "native/Hosts/Model/RemoteHosts.swift",
            ],
            ownership: .native, content: [.credentials, .identifiers], records: .host,
            copies: [
                DataCopySpec(.primary, .file(.appSupport, ["Hosts", "<host>.json"]), .json),
                DataCopySpec(.primary, .defaults(["RemoteHostsInstallationSecret"]), .defaults),
            ],
            retention: .userManaged, today: "Unpairing removes the host's file; the installation secret stays.",
            support: DataSupport(export: .notApplicable, delete: .adapterPending, hold: .userActionsIgnoreHolds),
            followUp: .secrets),
        DataStoreEntry(
            .companionPairings,
            "The companion app's paired hosts, active host, per-host preferences and installation secret.",
            owners: ["Companion/NativeCompanion/Model/CompanionDevice.swift"], ownership: .native,
            content: [.credentials, .identifiers], records: .host,
            copies: [
                DataCopySpec(.primary, .keychain(service: "native.companion.paired-hosts"), .keychain),
                DataCopySpec(
                    .primary, .defaults(["installationSecret", "activeHost", "host.<host>.preferences"]), .defaults),
            ],
            retention: .userManaged, today: "Forgetting a host removes its item and preferences.",
            support: DataSupport(export: .notApplicable, delete: .adapterPending, hold: .userActionsIgnoreHolds),
            followUp: .secrets),
        DataStoreEntry(
            .searchIndex,
            "Searchable copies of transcripts: titles, folders, message text, and how far each agent history file"
                + " has been read.",
            owners: [
                "Packages/Search/Sources/Search/SearchStore.swift",
                "Packages/Search/Sources/Search/SearchStore+Retention.swift",
                "native/Search/TranscriptSearchBackfill.swift",
            ],
            ownership: .native, content: [.userContent, .paths, .commands], records: .session,
            copies: [
                DataCopySpec(
                    .primary, .file(.appSupport, ["search-index.sqlite"]),
                    .sqlite(tables: ["sessions", "items", "items_fts", "sources", "meta"])),
                DataCopySpec(.writeAheadLog, .file(.appSupport, ["search-index.sqlite-wal"]), .sqlite(tables: [])),
                DataCopySpec(.sharedMemory, .file(.appSupport, ["search-index.sqlite-shm"]), .sqlite(tables: [])),
            ],
            retention: .policy(.searchRetentionDays),
            today: "Retention deletes sessions last active before the cutoff (one without a time is kept) with"
                + " their `sources` rows, then compacts and vacuums the file, at most once a day. Excluding a"
                + " folder removes its sessions without vacuuming; clearing the index drops and vacuums it.",
            support: .pendingPruned, reimportedFrom: [.agentHistories, .sessionCatalog], followUp: .search),
        DataStoreEntry(
            .automation,
            "Goals, automations and workflows with their runs and the tasks they started: objectives, prompts,"
                + " outputs and folders.",
            owners: [
                "Packages/Automation/Sources/NativeAutomation/AutomationStorage.swift",
                "native/Automation/Integration/StepTaskRecords.swift",
            ],
            ownership: .native, content: [.userContent, .paths, .identifiers], records: .automation,
            copies: automationFiles(["goals.json", "automations.json", "workflow-runs.json", "workflow-tasks.json"]),
            retention: .ownerRule(
                "50 runs per automation, 100 workflow runs, step-task records cut to 500 past 1,000; goals unbounded"),
            today: "Old runs drop past those limits; deleting an automation or a goal removes it.",
            support: .pendingPruned, followUp: .automation),
        DataStoreEntry(
            .expeditions, "Expeditions and the tasks their crews ran.",
            owners: [
                "Packages/Automation/Sources/NativeAutomation/AutomationStorage.swift",
                "native/Expeditions/Integration/ExpeditionCrewRecords.swift",
            ],
            ownership: .native, content: [.userContent, .paths, .identifiers], records: .expedition,
            copies: automationFiles(["expeditions.json", "expedition-tasks.json"]),
            retention: .userManaged, today: "No limit; nothing prunes them.", support: .pending,
            followUp: .automation),
        DataStoreEntry(
            .expeditionDocuments, "Each expedition's logbook, route, debrief, reports and checkpoints.",
            owners: ["Packages/Expeditions/Sources/NativeExpeditions/ExpeditionDocuments.swift"], ownership: .native,
            content: [.userContent], records: .expedition,
            copies: [DataCopySpec(.primary, .file(.nativeHome, ["expeditions", "<expedition>"]), .files)],
            retention: .userManaged, today: "Nothing deletes them; checkpoints are written read-only.",
            support: .pending, followUp: .automation),
    ]

    /// Automation keeps its files in Application Support, or wherever `automationDataDirectory` says.
    private static func automationFiles(_ names: [String]) -> [DataCopySpec] {
        names.flatMap { name in
            [
                DataCopySpec(.primary, .file(.appSupport, [name]), .json),
                DataCopySpec(.primary, .chosenFolder(setting: "automationDataDirectory", [name]), .json),
            ]
        }
    }
}
