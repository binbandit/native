import SwiftUI

extension SettingsPane.ID {
    static let git = Self("git")
}

extension SettingsPane {
    static let git = SettingsPane(
        id: .git,
        title: "Git",
        systemImage: "arrow.triangle.branch",
        group: .agents,
        order: 25,
        keywords: ["branch", "worktree", "prefix", "env", "archive"],
        searchEntries: {
            [
                SettingsSearchEntry(
                    id: GitSettingsPage.prefixRow, title: "Branch prefix", keywords: ["username", "github"]),
                SettingsSearchEntry(
                    id: GitSettingsPage.workspaceRow, title: "New tasks get", keywords: ["worktree", "branch"]),
                SettingsSearchEntry(
                    id: GitSettingsPage.envFilesRow, title: "Files to copy into new worktrees", keywords: [".env"]),
            ]
        },
        content: { GitSettingsPage() }
    )
}

/// Git settings: how new tasks get their branch and worktree, and what archiving does.
struct GitSettingsPage: View {
    static let prefixRow = SettingsRowID("git.prefix")
    static let workspaceRow = SettingsRowID("git.workspace")
    static let envFilesRow = SettingsRowID("git.env-files")

    @Environment(GitSettings.self) private var settings
    @Environment(SettingsPresentation.self) private var presentation

    var body: some View {
        @Bindable var settings = settings
        SettingsPage {
            SettingsHeader(
                "Git",
                description: Text("How new tasks get their branch and worktree. Everything runs with your own git."))
            SettingsRowGroup {
                SettingsRow(
                    id: Self.prefixRow, "Branch prefix",
                    description: Text(
                        "New branches start with it, like \(settings.branchPrefix(gitHubLogin: "you"))fix-login-bug.")
                ) {
                    HStack(spacing: DS.Space.sm) {
                        if settings.branchPrefixMode == .custom {
                            TextField("prefix", text: $settings.customBranchPrefix)
                                .settingsField()
                                .frame(width: GitMetrics.prefixFieldWidth)
                        }
                        SettingsSelect(
                            label: "Branch prefix", selection: $settings.branchPrefixMode,
                            options: GitSettings.BranchPrefixMode.allCases.map { .init(value: $0, title: $0.title) })
                    }
                }
                SettingsRow(
                    "Rename branches from the task",
                    description: Text("A new task's branch is renamed after its title, until it's pushed.")
                ) {
                    SettingsSwitch("Rename branches from the task", isOn: $settings.renamesBranches)
                }
                SettingsRow(
                    id: Self.workspaceRow, "New tasks get",
                    description: Text(
                        "A worktree keeps parallel tasks from editing the same files. Worktrees live in ~/.native/worktrees."
                    )
                ) {
                    SettingsSelect(
                        label: "New tasks get", selection: $settings.newTaskWorkspace,
                        options: GitSettings.NewTaskWorkspace.allCases.map { .init(value: $0, title: $0.title) })
                }
                SettingsRow(
                    id: Self.envFilesRow, "Files to copy into new worktrees",
                    description: Text("Ignored files a task needs to run, as gitignore patterns separated by commas.")
                ) {
                    TextField(".env*", text: patterns)
                        .settingsField()
                        .frame(width: GitMetrics.patternsFieldWidth)
                }
                SettingsRow(
                    "Delete the branch when archiving",
                    description: Text("Its commits stay reachable, so restoring the task brings the branch back.")
                ) {
                    SettingsSwitch("Delete the branch when archiving", isOn: $settings.deletesBranchOnArchive)
                }
                SettingsRow(
                    "Setup and teardown scripts",
                    description: Text(
                        "Commands that run as worktrees are made and removed, and as tasks start, finish turns and are deleted."
                    )
                ) {
                    Button("Open Scripts") { presentation.open(.scripts) }
                }
            }
        }
    }

    /// The patterns as one comma-separated field.
    private var patterns: Binding<String> {
        Binding(
            get: { settings.envFilePatterns.joined(separator: ", ") },
            set: { text in
                settings.envFilePatterns = text.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
                    .filter { !$0.isEmpty }
            }
        )
    }
}

#if DEBUG
#Preview("Git settings") {
    DSPreviewPair {
        GitSettingsPage()
            .settingsPreviewPage()
    }
    .environment(GitSettings(defaults: PreviewUserDefaults()))
    .environment(SettingsPresentation())
}
#endif
