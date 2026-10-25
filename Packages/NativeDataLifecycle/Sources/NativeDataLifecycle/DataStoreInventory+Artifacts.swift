extension DataStoreInventory {
    /// Attachments, temporary files, pull request artifacts and what tasks leave in git.
    static let artifactEntries: [DataStoreEntry] = [
        DataStoreEntry(
            .attachments, "Pasted images and pull request task briefs written for an agent to read.",
            owners: [
                "Packages/ACP/Sources/ACP/Prompt/PromptAttachment+Loading.swift",
                "native/PullRequestTasks/Model/PullRequestTaskCheckout.swift",
            ],
            ownership: .native, content: [.userContent], records: .session,
            copies: [DataCopySpec(.temporary, .file(.temporary, ["Native Attachments", "<attachment>"]), .files)],
            retention: .ownerRule("until the system clears temporary files"), today: "Native never removes them.",
            support: .pending, followUp: .appRecords),
        DataStoreEntry(
            .workingFiles,
            "Short-lived working files: artifact previews, terminal configuration, sign-in status, skill staging and"
                + " terminal resource links.",
            owners: [
                "Packages/ACP/Sources/ACP/Artifacts/ArtifactPreviewFile.swift",
                "native/Terminal/Engine/GhosttyConfigBuilder.swift", "native/AgentCatalog/AgentTerminalSignInRun.swift",
                "Packages/Skills/Sources/Skills/Files/SkillFileSystem.swift",
            ],
            ownership: .native, content: [.userContent, .configuration], records: .store,
            copies: [
                DataCopySpec(.temporary, .file(.temporary, ["Native-Artifact-<id>"]), .files),
                DataCopySpec(.temporary, .file(.temporary, ["native-terminal-<id>"]), .files),
                DataCopySpec(.temporary, .file(.temporary, ["native-sign-in-<id>.status"]), .files),
                DataCopySpec(.temporary, .file(.temporary, ["native-skills-<id>"]), .files),
                DataCopySpec(.temporary, .file(.caches, ["ghostty-resources"]), .files),
            ],
            retention: .ownerRule("removed by the code that made them"),
            today: "Previews close with their viewer, terminal configuration goes right after use, sign-in status"
                + " when sign-in ends and skill staging on install or discard; terminal links are rebuilt at launch.",
            support: .pendingPruned, followUp: .appRecords),
        DataStoreEntry(
            .pullRequestQuestions, "Pull request context written for questions about it: its description and diffs.",
            owners: ["native/GitHub/Ask/Model/PullRequestAskCenter.swift"], ownership: .native,
            content: [.userContent, .paths], records: .pullRequest,
            copies: [
                DataCopySpec(
                    .primary, .file(.appSupport, ["PullRequestQuestions", "<host>", "<owner>", "<name>-<number>"]),
                    .files)
            ],
            retention: .ownerRule("kept indefinitely"),
            today: "Diffs are replaced when the context is written again; folders are never removed.",
            support: .pending, followUp: .appRecords),
        DataStoreEntry(
            .pullRequestClones,
            "Repositories cloned to start pull request tasks, in the clone folder (by default the user's developer"
                + " folder). Native made them, but they are"
                + " ordinary checkouts the user may work in, so their owner isn't established.",
            owners: ["native/PullRequestTasks/Model/PullRequestTaskCheckout.swift"], ownership: .unknown,
            content: [.userContent, .paths], records: .repository,
            copies: [
                DataCopySpec(
                    .primary, .chosenFolder(setting: "pullRequestTasks.cloneFolder", ["<repository>"]), .gitWorktree)
            ],
            retention: .userManaged, today: "Native never removes them.", support: .outside, followUp: nil),
        DataStoreEntry(
            .taskWorktrees, "Worktrees made for tasks, with everything the agent and the user changed in them.",
            owners: ["native/Git/Model/GitStore+TaskWorkspaces.swift", "native/Git/Cleanup/GitCleanupModel+Run.swift"],
            ownership: .native, content: [.userContent, .paths], records: .session,
            copies: [
                DataCopySpec(.primary, .file(.nativeHome, ["worktrees", "<repository>", "<task>"]), .gitWorktree),
                DataCopySpec(
                    .primary, .chosenFolder(setting: "gitWorktreesFolder", ["<repository>", "<task>"]), .gitWorktree),
            ],
            retention: .followsRecord(.session),
            today: "Removing a task's worktree takes a checkpoint first; Git Cleanup moves leftover folders to the"
                + " Trash.",
            support: .pending, followUp: .git),
        DataStoreEntry(
            .nativeRefs,
            "Refs and config Native adds to repositories: task checkpoints, archived branches and worktrees,"
                + " worktree bases and branch notes.",
            owners: [
                "Packages/Git/Sources/Git/Repository/Repository+Checkpoints.swift",
                "Packages/Git/Sources/Git/Repository/Repository+TaskBranches.swift",
                "Packages/Git/Sources/Git/Repository/Repository+ArchivedWorktrees.swift",
                "Packages/Git/Sources/Git/Repository/Repository+WorktreeBase.swift",
            ],
            ownership: .native, content: [.userContent, .paths], records: .session,
            copies: [
                DataCopySpec(
                    .primary,
                    .gitRefs([
                        "refs/native-checkpoints/*", "refs/native-archived-branches/*", "refs/native/worktree-bases/*",
                        "nativeArchivedWorktree.*", "nativeArchivedBranch.*", "branch.*.native*",
                    ]), .gitRefs)
            ],
            retention: .ownerRule("checkpoints kept indefinitely; a worktree base until its fetch ends"),
            today: "Restoring an archived branch deletes its ref; nothing deletes checkpoints.", support: .pending,
            followUp: .git),
        DataStoreEntry(
            .repositoryHistory,
            "Git objects and reflogs in the user's repositories that still hold snapshots Native made: turn"
                + " baselines, removed checkpoints and task commits.",
            owners: ["native/Git/Model/GitTurnBaselines.swift"], ownership: .customer, content: [.userContent],
            records: .repository,
            copies: [
                DataCopySpec(.gitObjects, .elsewhere(.repository, "loose and packed objects"), .gitObjects),
                DataCopySpec(.reflog, .elsewhere(.repository, "reflogs of the branches tasks used"), .gitRefs),
            ],
            retention: .external, today: "Left to git gc and the repository's own settings.", support: .outside,
            followUp: nil),
    ]

    /// Plugins, skills, components, downloaded resources and diagnostics.
    static let resourceEntries: [DataStoreEntry] = [
        DataStoreEntry(
            .plugins, "Plugins the user installed from manifests, with their assets.",
            owners: ["native/Plugins/PluginRegistry.swift"], ownership: .customer,
            content: [.commands, .configuration],
            records: .plugin,
            copies: [
                DataCopySpec(.primary, .file(.nativeHome, ["plugins", "<plugin>"]), .files),
                DataCopySpec(.primary, .chosenFolder(setting: "pluginsDirectory", ["<plugin>"]), .files),
            ],
            retention: .userManaged, today: "The user adds and removes them.", support: .outside, followUp: nil),
        DataStoreEntry(
            .componentCaches,
            "Verified component bytes, managed adapter installs and remote plugin asset blobs, each in a folder its"
                + " caller chooses.",
            owners: [
                "Packages/HostUpdater/Sources/HostUpdater/PinnedComponentCache.swift",
                "Packages/NativeHost/Sources/NativeHost/ManagedAdapterInstaller.swift",
                "Packages/NativeHost/Sources/NativeHostClient/PluginAssets.swift",
            ],
            ownership: .native, integration: .dormant, content: [.cache], records: .store,
            copies: [DataCopySpec(.primary, .undetermined, .files)], retention: .undetermined,
            today: "Nothing constructs them in production yet.", support: .none, followUp: nil),
        DataStoreEntry(
            .skillsLibrary, "Which skills Native installed, from where, and their switches.",
            owners: ["native/Skills/Model/SkillLibrary.swift"], ownership: .native, content: [.paths, .configuration],
            records: .skill, copies: [DataCopySpec(.primary, .file(.appSupport, ["skills.json"]), .json)],
            retention: .userManaged, today: "Uninstalling a skill removes its entry.", support: .pending,
            followUp: .appRecords),
        DataStoreEntry(
            .skillsInstalled, "Skill files installed into agents' skill folders, for the user or for a project.",
            owners: ["Packages/Skills/Sources/Skills/Install/SkillInstaller.swift"], ownership: .externalAgent,
            content: [.commands, .configuration], records: .skill,
            copies: [
                DataCopySpec(.primary, .elsewhere(.agentHome, "each agent's user or project skill folder"), .files)
            ],
            retention: .userManaged, today: "Uninstalling moves the files to Skills Trash.",
            support: DataSupport(export: .notApplicable, delete: .adapterPending, hold: .ownerOutsideNative),
            followUp: .externalAgents),
        DataStoreEntry(
            .skillsTrash, "Uninstalled skills, kept so the uninstall can be undone.",
            owners: ["native/Skills/Model/SkillLibrary.swift"], ownership: .native,
            content: [.commands, .configuration],
            records: .skill, copies: [DataCopySpec(.trash, .file(.appSupport, ["Skills Trash", "<entry>"]), .files)],
            retention: .ownerRule("never emptied"), today: "Nothing empties it.", support: .pending,
            followUp: .appRecords),
        DataStoreEntry(
            .agentIcons, "Agent icons and the registry index they came from.",
            owners: ["native/AgentIcons/AgentIconRegistry.swift"], ownership: .native, content: [.cache],
            records: .store,
            copies: [
                DataCopySpec(.primary, .file(.appSupport, ["AgentIcons", "registry.json"]), .json),
                DataCopySpec(.primary, .file(.appSupport, ["AgentIcons", "registry-<hash>.json"]), .json),
                DataCopySpec(.primary, .file(.appSupport, ["AgentIcons", "icons", "<icon>.svg"]), .files),
            ],
            retention: .ownerRule("index refreshed daily, icons weekly"),
            today: "Replaced when refreshed; never pruned.",
            support: .cache, followUp: .appRecords),
        DataStoreEntry(
            .projectIcons, "Icons detected in or chosen for each project.",
            owners: ["native/ProjectIcons/ProjectIconStore.swift"], ownership: .native,
            content: [.userContent, .cache],
            records: .project,
            copies: [
                DataCopySpec(.primary, .file(.appSupport, ["ProjectIcons", "<kind>-<project>.<format>"]), .files),
                DataCopySpec(.primary, .defaults(["projectIcons.choices"]), .defaults),
            ],
            retention: .followsRecord(.project), today: "Replaced when detected again or changed; never pruned.",
            support: .pending, followUp: .appRecords),
        DataStoreEntry(
            .celebrationAssets, "Downloaded celebration artwork packs.",
            owners: ["native/Celebrations/CelebrationAssetStore.swift"], ownership: .native, content: [.cache],
            records: .store,
            copies: [DataCopySpec(.primary, .file(.appSupport, ["CelebrationAssets", "<edition>"]), .files)],
            retention: .untilReplaced, today: "Replaced by newer packs; never pruned.", support: .cache,
            followUp: .appRecords),
        DataStoreEntry(
            .appUpdates, "Update downloads and installer state the update framework keeps.",
            owners: ["native/Updates/SparkleUpdateDriver.swift"], ownership: .native, content: [.cache],
            records: .store,
            copies: [DataCopySpec(.primary, .elsewhere(.caches, "the update framework's own folders"), .ownerDefined)],
            retention: .ownerRule("the update framework's own"), today: "Managed by the update framework.",
            support: .none, followUp: nil),
        DataStoreEntry(
            .telemetrySentLog, "A readable log of the telemetry Native sent: event names, counts and versions.",
            owners: ["Packages/Telemetry/Sources/NativeTelemetry/TelemetrySentLog.swift"], ownership: .native,
            content: [.diagnostics, .identifiers], records: .store,
            copies: [DataCopySpec(.primary, .file(.appSupport, ["Telemetry", "sent.jsonl"]), .jsonLines)],
            retention: .ownerRule("the newest 200 entries"), today: "Old entries drop; its clear action has no caller.",
            support: .pendingPruned, followUp: .appRecords),
        DataStoreEntry(
            .crashReportCache, "Error and crash reports waiting to send while diagnostics are on.",
            owners: ["native/Telemetry/SentryTelemetry.swift"], ownership: .native, content: [.diagnostics],
            records: .store, copies: [DataCopySpec(.primary, .file(.caches, ["SentryTelemetry"]), .files)],
            retention: .ownerRule("until diagnostics turn off"), today: "Turning diagnostics off removes the cache.",
            support: .pendingPruned, followUp: .appRecords),
        DataStoreEntry(
            .commandCoverage,
            "Counts of programs that approvals saw and command knowledge doesn't describe: program names only.",
            owners: [
                "native/CommandKnowledge/CommandKnowledgeCenter.swift",
                "Packages/ApprovalAnalysis/Sources/ApprovalAnalysis/UnknownCommandCounts.swift",
            ],
            ownership: .native, content: [.diagnostics, .commands], records: .store,
            copies: [DataCopySpec(.primary, .file(.appSupport, ["CommandKnowledge", "unknown-programs.json"]), .json)],
            retention: .ownerRule("up to 256 programs"),
            today: "Clear Counts removes them, and policy can turn counting off.", support: .pendingPruned,
            followUp: .appRecords),
    ]
}
