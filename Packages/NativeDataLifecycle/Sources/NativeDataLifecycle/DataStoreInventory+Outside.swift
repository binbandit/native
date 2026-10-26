extension DataStoreInventory {
    /// Copies of the user's work that others own. Native lists them so a result can name what it
    /// couldn't reach; it never reads them to do so.
    static let outsideEntries: [DataStoreEntry] = [
        DataStoreEntry(
            .systemRecords,
            "What the operating system keeps from Native: unified log messages, crash reports and Notification Center"
                + " history. A portable host's log goes to its supervisor.",
            owners: [
                "native/Usage/System/UserNotificationPoster.swift",
                "Packages/NativeHost/Sources/NativeHostProtocol/Platform.swift",
            ],
            ownership: .operatingSystem, content: [.userContent, .paths, .commands, .diagnostics], records: .store,
            copies: [
                DataCopySpec(
                    .primary, .elsewhere(.operatingSystem, "unified logging, crash reports, Notification Center"),
                    .ownerDefined)
            ],
            retention: .external, today: "The system expires them on its own schedule.", support: .outside,
            followUp: nil),
        DataStoreEntry(
            .agentHistories,
            "Each agent's own conversation history, wherever the agent keeps it. Native reads it to load and search"
                + " tasks.",
            owners: ["Packages/Search/Sources/Search/History/"], ownership: .externalAgent,
            content: [.userContent, .paths, .commands], records: .session,
            copies: [DataCopySpec(.primary, .elsewhere(.agentHome, "the agent's own history files"), .ownerDefined)],
            retention: .external, today: "Native never deletes them; an agent may offer its own way to.",
            support: DataSupport(export: .adapterPending, delete: .adapterPending, hold: .ownerOutsideNative),
            followUp: .externalAgents),
        DataStoreEntry(
            .agentConfiguration,
            "Agents' own settings and MCP and plugin configuration, which Native reads and changes only through the"
                + " agent's command line.",
            owners: ["native/AgentCatalog/"], ownership: .externalAgent, content: [.commands, .paths, .configuration],
            records: .agent,
            copies: [DataCopySpec(.primary, .elsewhere(.agentHome, "the agent's configuration files"), .ownerDefined)],
            retention: .external, today: "Changed only through the agent's own command line.", support: .outside,
            followUp: nil),
        DataStoreEntry(
            .agentCredentials,
            "Agents' own sign-in. Native never reads it; it shows only the status an agent reports.", owners: [],
            ownership: .externalAgent, content: [.credentials], records: .agent,
            copies: [
                DataCopySpec(.primary, .elsewhere(.agentHome, "wherever the agent keeps its sign-in"), .ownerDefined)
            ],
            retention: .external, today: "Signing out belongs to the agent.", support: .outside, followUp: nil),
        DataStoreEntry(
            .toolCredentials,
            "Sign-in for tools Native runs: the GitHub command line, git credential helpers, SSH keys.",
            owners: [], ownership: .customer, content: [.credentials], records: .store,
            copies: [DataCopySpec(.primary, .elsewhere(.customerManaged, "each tool's own store"), .ownerDefined)],
            retention: .external, today: "Native never reads or removes them.", support: .outside, followUp: nil),
        DataStoreEntry(
            .packageCaches, "Package manager caches and global installs used to run agent adapters.",
            owners: ["Packages/ACP/Sources/ACP/NpxLaunch.swift"], ownership: .customer, content: [.cache],
            records: .store,
            copies: [
                DataCopySpec(
                    .primary, .elsewhere(.customerManaged, "the package manager's cache and global installs"),
                    .ownerDefined)
            ],
            retention: .external, today: "Managed by the package manager.", support: .outside, followUp: nil),
        DataStoreEntry(
            .customerBackups,
            "Copies beyond Native's reach: Time Machine and other backups, file system snapshots, the Trash, synced"
                + " folders, and git remotes and forks.",
            owners: [], ownership: .customer, content: [.userContent, .paths, .commands, .credentials],
            records: .store,
            copies: [
                DataCopySpec(
                    .primary, .elsewhere(.customerManaged, "backups, snapshots, the Trash, sync services, git remotes"),
                    .ownerDefined)
            ],
            retention: .external, today: "Native can't see or remove them; every deletion result lists them.",
            support: .outside, followUp: nil),
        DataStoreEntry(
            .customerExports,
            "What the user took out of Native: exported patches and transcripts, copied text, files opened in other"
                + " apps, and terminal history and output.",
            owners: ["native/Platform/PlatformArtifactActions.swift"], ownership: .customer,
            content: [.userContent, .paths, .commands], records: .store,
            copies: [
                DataCopySpec(
                    .primary, .elsewhere(.customerManaged, "wherever the user saved or pasted it"), .ownerDefined)
            ],
            retention: .external, today: "Belongs to the user once exported.", support: .outside, followUp: nil),
    ]
}
