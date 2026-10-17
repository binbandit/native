import SwiftUI
import UniformTypeIdentifiers

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
        keywords: ["branch", "worktree", "prefix", "env", "setup script", "archive"],
        searchEntries: {
            [
                SettingsSearchEntry(
                    id: GitSettingsPage.prefixRow, title: "Branch prefix", keywords: ["username", "github"]),
                SettingsSearchEntry(
                    id: GitSettingsPage.workspaceRow, title: "New tasks get", keywords: ["worktree", "branch"]),
                SettingsSearchEntry(
                    id: GitSettingsPage.envFilesRow, title: "Files to copy into new worktrees", keywords: [".env"]),
                SettingsSearchEntry(
                    id: GitSettingsPage.scriptsRow, title: "Setup scripts", keywords: ["setup", "install"]),
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
    static let scriptsRow = SettingsRowID("git.scripts")

    @Environment(GitSettings.self) private var settings
    @State private var isChoosingProject = false
    @State private var editingScript: URL?

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
                                .textFieldStyle(.roundedBorder)
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
                        .textFieldStyle(.roundedBorder)
                        .frame(width: GitMetrics.patternsFieldWidth)
                }
                SettingsRow(
                    "Delete the branch when archiving",
                    description: Text("Its commits stay reachable, so restoring the task brings the branch back.")
                ) {
                    SettingsSwitch("Delete the branch when archiving", isOn: $settings.deletesBranchOnArchive)
                }
            }
            SettingsSubheading(
                "Setup scripts", note: "Run in each new worktree of the project, after env files are copied."
            )
            .settingsRevealTarget(Self.scriptsRow)
            SettingsRowGroup {
                ForEach(settings.setupScripts.keys.sorted(), id: \.self) { path in
                    let root = URL(filePath: path, directoryHint: .isDirectory)
                    SettingsRow(root.lastPathComponent, description: Text(root.abbreviatedPath)) {
                        HStack(spacing: DS.Space.sm) {
                            Button("Edit…") { editingScript = root }
                                .buttonStyle(.ds(.secondary))
                            Button("Remove", role: .destructive) { settings.setSetupScript("", forProjectAt: root) }
                                .buttonStyle(.ds(.ghost))
                        }
                    }
                }
                SettingsRow(
                    settings.setupScripts.isEmpty ? "No setup scripts yet" : "Another project",
                    description: Text("Install dependencies or start services for a project's new worktrees.")
                ) {
                    Button("Add Script…") { isChoosingProject = true }
                        .buttonStyle(.ds(.secondary))
                }
            }
        }
        .fileImporter(isPresented: $isChoosingProject, allowedContentTypes: [.folder]) { result in
            if case .success(let url) = result { editingScript = url }
        }
        .sheet(isPresented: Binding(get: { editingScript != nil }, set: { if !$0 { editingScript = nil } })) {
            if let editingScript {
                GitSetupScriptEditor(settings: settings, root: editingScript)
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
