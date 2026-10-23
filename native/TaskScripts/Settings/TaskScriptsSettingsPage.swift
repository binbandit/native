import NativePolicy
import SwiftUI
import TaskScripts

extension SettingsPane.ID {
    static let scripts = Self("scripts")
}

extension SettingsPane {
    static let scripts = SettingsPane(
        id: .scripts,
        title: "Scripts",
        systemImage: "terminal",
        group: .agents,
        // After Git, GitHub and AI Instructions.
        order: 28,
        keywords: ["setup", "teardown", "hook", "worktree", "lifecycle", "script", "turn finished", ".native"],
        searchEntries: {
            TaskScriptEvent.allCases.map {
                SettingsSearchEntry(
                    id: TaskScriptsSettingsPage.row($0), title: "\($0.title) script", description: $0.summary,
                    keywords: ["script", "hook"], plainly: $0.plainlyCopy)
            } + [
                SettingsSearchEntry(
                    id: TaskScriptsSettingsPage.variablesRow, title: "Script environment variables",
                    keywords: ["NATIVE_WORKTREE_PATH", "env"], plainly: .init(title: "Variables"))
            ]
        },
        content: { TaskScriptsSettingsPage() }
    )
}

/// Settings ▸ Scripts: the user's own commands for every project, one per event, with what each
/// project adds and the variables every script gets.
struct TaskScriptsSettingsPage: View {
    static func row(_ event: TaskScriptEvent) -> SettingsRowID {
        SettingsRowID("scripts.\(event.rawValue)")
    }

    static let projectsRow = SettingsRowID("scripts.projects")
    static let variablesRow = SettingsRowID("scripts.variables")

    @Environment(TaskScriptSettings.self) private var settings
    @Environment(AppModel.self) private var model
    @State private var editing: TaskScriptEditorSheet.Target?
    @State private var editingProject: TaskScriptProjectSheet.Project?
    /// Projects with scripts of their own, kept here or committed to their repository.
    @State private var customizedProjects: [Project] = []

    var body: some View {
        SettingsPage {
            SettingsHeader(
                "Scripts",
                description: Text(
                    "Your own commands, run with your shell in a task's folder: when Native makes its worktree, when it starts, after each turn, before its worktree is removed and once it's deleted."
                ), plainly: .init(title: "Scripts", description: "Your commands, run at each stage of a task's work."))
            SettingsRowGroup {
                ForEach(TaskScriptEvent.allCases) { event in
                    SettingsRow(
                        id: Self.row(event), event.title, plainly: event.plainlyCopy, description: Text(event.summary),
                        detail: detail(event)
                    ) {
                        Button(settings.script(for: event).isEmpty ? "Add…" : "Edit…") {
                            editing = .init(event: event, scope: .global)
                        }
                    }
                }
            }
            .settingsManaged(by: .taskScriptsUser)
            SettingsSubheading(
                "Projects",
                note:
                    "A project can run its own script for an event, after the global one or instead of it. A repository can commit them as .native/setup.sh and so on; they show as From the repo."
            )
            .settingsRevealTarget(Self.projectsRow)
            if customizedProjects.isEmpty {
                SettingsNote("No project has scripts of its own") {
                    Text("Each project's settings have its scripts, and Native lists the projects that have some here.")
                }
            } else {
                SettingsRowGroup {
                    ForEach(customizedProjects) { project in
                        SettingsRow(project.name, description: Text(project.url.abbreviatedPath)) {
                            Button("Edit…") { editingProject = .init(url: project.url) }
                        }
                    }
                }
            }
            SettingsSubheading(
                "Variables", note: "Every script gets these, and runs with the task's folder as its working directory."
            )
            .settingsRevealTarget(Self.variablesRow)
            SettingsNote {
                TaskScriptVariablesList()
            }
        }
        .task { refreshProjects() }
        .sheet(item: $editing) { target in
            TaskScriptEditorSheet(target: target)
        }
        .sheet(item: $editingProject, onDismiss: refreshProjects) { project in
            TaskScriptProjectSheet(project: project)
        }
    }

    /// The script's first line and its time limit.
    private func detail(_ event: TaskScriptEvent) -> Text {
        let limit = "Stops after \(TaskScriptTimeouts.title(settings.timeout(for: event)))."
        let firstLine = settings.script(for: event).split(separator: "\n").first { !$0.hasPrefix("#!") }
        guard let firstLine else { return Text(limit) }
        return Text("\(Text(verbatim: String(firstLine)).font(.dsMonoCaption))  ·  \(limit)")
    }

    private func refreshProjects() {
        let customized = Set(settings.customizedProjects.map(TaskScriptConfiguration.key(for:)))
        customizedProjects = model.projects.all.filter { project in
            customized.contains(TaskScriptConfiguration.key(for: project.url))
                || !settings.repositoryScripts(at: project.url).isEmpty
        }
    }
}

/// A project's scripts in a sheet, for editing them from Settings ▸ Scripts.
struct TaskScriptProjectSheet: View {
    struct Project: Identifiable {
        let url: URL
        var id: URL { url }
    }

    let project: Project

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.xl) {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Text(project.url.lastPathComponent)
                        .settingsText(.title)
                        .foregroundStyle(.dsTextPrimary)
                        .accessibilityAddTraits(.isHeader)
                    ProjectScriptsSection(projectRoot: project.url)
                }
                .padding(DS.Space.xxl)
            }
            HStack {
                Spacer()
                Button("Done") { dismiss() }
                    .buttonStyle(.ds(.primary, size: .large))
                    .keyboardShortcut(.defaultAction)
            }
            .padding([.horizontal, .bottom], DS.Space.xxl)
        }
        .frame(width: TaskScriptMetrics.editorSheetWidth, height: TaskScriptMetrics.logMaxHeight + DS.Space.xxxl * 4)
        .background(.dsBackground)
    }
}

#if NATIVE_PREVIEWS_WIP
#Preview("Scripts settings") {
    DSPreviewPair {
        TaskScriptsSettingsPage()
            .settingsPreviewPage()
    }
    .environment(TaskScriptsPreviewFixtures.settings())
    .environment(TaskScriptsPreviewFixtures.center())
    .environment(AppModel.preview())
}

#Preview("Project scripts sheet") {
    DSPreviewPair {
        TaskScriptProjectSheet(project: TaskScriptProjectSheet.Project(url: TaskScriptsPreviewFixtures.project))
    }
    .environment(TaskScriptsPreviewFixtures.settings())
}
#endif
