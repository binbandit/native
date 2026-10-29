import Git
import NativePolicy
import SwiftUI
import TaskScripts

/// The project owns cache choices; its existing setup script owns installation and task output.
struct WorktreeWarmProjectSection: View {
    let project: Project

    @Environment(GitSettings.self) private var settings
    @Environment(TaskScriptSettings.self) private var scripts
    @Environment(\.undoManager) private var undoManager
    @State private var editing: TaskScriptEditorSheet.Target?
    @State private var repositorySetup = false
    @State private var folderDraft: String?

    private var configuration: WorktreeWarmSettings { settings.warmWorktree(forProjectAt: project.url) }
    private var invalidFolders: [String] { configuration.folders.filter { !WorktreeWarmSettings.isValidFolder($0) } }

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.lg) {
            SettingsSubheading(
                "Warm worktrees",
                note:
                    "Bring installed dependencies and build caches into new tasks. APFS copies share storage until files change. Other volumes start without copies."
            )
            SettingsRowGroup {
                SettingsRow(
                    id: ProjectSettingsRows(project: project.id).warmWorktree, "Bring project files along",
                    description: Text(
                        "Only ignored folders inside this project are eligible. Existing task files stay in place.")
                ) {
                    SettingsSwitch("Bring project files along", isOn: binding(\.enabled))
                }
                SettingsRow(
                    "Folders to bring along",
                    description: Text(
                        "Names match at any depth. Use a relative path for one folder. Separate entries with commas.")
                ) {
                    TextField("node_modules, .build", text: folders, axis: .vertical)
                        .settingsField()
                        .frame(width: WorktreeWarmMetrics.foldersWidth)
                        .lineLimit(3...6)
                        .accessibilityLabel("Folders to bring along")
                        .onSubmit { folderDraft = nil }
                }
                .disabled(!configuration.enabled)
                SettingsRow(
                    "Include local env files",
                    description: Text(
                        "Also bring untracked .env and .env.local files. They may contain credentials. Off unless you allow it here."
                    )
                ) {
                    SettingsSwitch("Include local env files", isOn: binding(\.includesEnvironmentFiles))
                }
                .disabled(!configuration.enabled)
                SettingsRow(
                    "Setup command",
                    description: Text(
                        "Runs once in each new worktree after copies finish. The agent waits; output, Retry and Skip Setup stay in the task."
                    )
                ) {
                    Button(repositorySetup ? "Show…" : hasSetup ? "Edit…" : "Add…") {
                        editing = .init(
                            event: .setup,
                            scope: repositorySetup ? .repository(project: project.url) : .project(project.url))
                    }
                }
                .settingsManaged(by: repositorySetup ? .taskScriptsRepository : .taskScriptsUser)
            }
            if !invalidFolders.isEmpty {
                SettingsNote(
                    "Some folders will be skipped",
                    systemImage: "exclamationmark.triangle"
                ) {
                    Text(
                        "Use relative folder names without .., .git or .env: \(invalidFolders.joined(separator: ", "))."
                    )
                }
            }
        }
        .sheet(item: $editing) { target in TaskScriptEditorSheet(target: target) }
        .task(id: project.url) { repositorySetup = scripts.repositoryScripts(at: project.url)[.setup] != nil }
        .onChange(of: project.url) { folderDraft = nil }
        .onChange(of: configuration.folders) { _, updated in
            if folderDraft.map(Self.parseFolders) != updated { folderDraft = nil }
        }
    }

    private var hasSetup: Bool { scripts.project(at: project.url).scripts[.setup] != nil }

    private func binding<Value>(_ keyPath: WritableKeyPath<WorktreeWarmSettings, Value>) -> Binding<Value> {
        Binding(
            get: { configuration[keyPath: keyPath] },
            set: { value in
                var updated = configuration
                updated[keyPath: keyPath] = value
                settings.setWarmWorktree(updated, forProjectAt: project.url, undoManager: undoManager)
            })
    }

    private var folders: Binding<String> {
        Binding(
            get: { folderDraft ?? configuration.folders.joined(separator: ", ") },
            set: { text in
                // Keep delimiters while typing, so a comma can start the next entry.
                folderDraft = text
                var updated = configuration
                updated.folders = Self.parseFolders(text)
                settings.setWarmWorktree(updated, forProjectAt: project.url, undoManager: undoManager)
            })
    }

    private static func parseFolders(_ text: String) -> [String] {
        text.split(separator: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
    }
}

#if DEBUG
#Preview("Warm worktrees - Project setup") {
    worktreeWarmPreview(.init())
}

#Preview("Warm worktrees - Copies off") {
    worktreeWarmPreview(.init(enabled: false))
}

#Preview("Warm worktrees - Invalid folders") {
    worktreeWarmPreview(.init(folders: ["node_modules", "../cache", ".env"], includesEnvironmentFiles: true))
}

#Preview("Warm worktrees - Setup configured") {
    worktreeWarmPreview(.init(), setup: "bun install")
}

@MainActor
private func worktreeWarmPreview(_ configuration: WorktreeWarmSettings, setup: String? = nil) -> some View {
    let app = AppModel.preview()
    let settings = GitSettings(defaults: PreviewUserDefaults())
    let scripts = TaskScriptSettings(defaults: PreviewUserDefaults())
    if let project = app.previewProject() {
        settings.setWarmWorktree(configuration, forProjectAt: project.url)
        if let setup { scripts.setProjectScript(setup, for: .setup, at: project.url) }
    }
    return DSPreviewPair {
        if let project = app.previewProject() {
            WorktreeWarmProjectSection(project: project).settingsPreviewPage()
        }
    }
    .environment(settings)
    .environment(scripts)
}
#endif
