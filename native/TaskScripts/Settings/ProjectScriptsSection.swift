import NativePolicy
import SwiftUI
import TaskScripts

/// One project's task scripts, for its settings: whether the scripts its repository commits may
/// run, and for each event what runs and where it comes from ("From the repo", "This project", or
/// the global one), with an editor for the project's own.
///
///     ProjectScriptsSection(projectRoot: project.url)
struct ProjectScriptsSection: View {
    @Environment(\.settingsPlainly) private var plainly
    @Environment(SettingsPresentation.self) private var presentation
    /// The project's main checkout.
    let projectRoot: URL

    @Environment(TaskScriptSettings.self) private var settings
    @State private var repository: [TaskScriptEvent: String] = [:]
    @State private var editing: TaskScriptEditorSheet.Target?

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.xxl) {
            SettingsSubheading(
                "Scripts",
                note:
                    "Commands this project's tasks run, after the global ones in Settings ▸ Scripts or instead of them. A repository can commit its own as .native/<event>.sh.",
                plainly: .init(
                    title: "Scripts",
                    description:
                        "Runs after the scripts for every project, or instead of them. A repository can commit its own as .native/<moment>.sh."
                )
            )
            if plainly {
                Button("Scripts for Every Project…") { presentation.open(.scripts) }
                    .buttonStyle(.settings)
            }
            SettingsRowGroup {
                SettingsRow(
                    "Run scripts from the repo", description: Text(repositoryDescription)
                ) {
                    SettingsSwitch(
                        "Run scripts from the repo",
                        isOn: Binding(
                            get: { settings.allowsRepositoryScripts(forProjectAt: projectRoot) },
                            set: { settings.setAllowsRepositoryScripts($0, forProjectAt: projectRoot) }))
                }
                .settingsManaged(by: .taskScriptsRepository)
                ForEach(TaskScriptEvent.allCases) { event in
                    row(event)
                }
            }
        }
        .task(id: projectRoot) { reload() }
        .sheet(item: $editing, onDismiss: reload) { target in
            TaskScriptEditorSheet(target: target)
        }
    }

    private func row(_ event: TaskScriptEvent) -> some View {
        let source = source(of: event)
        return SettingsRow(
            title: Text(event.title),
            plainly: .init(title: event.plainlyCopy.title, preservesDescription: true),
            description: Text(effect(of: event, source: source))
        ) {
            if let source, source != .global {
                SettingsBadge(source.label, systemImage: source == .repository ? "arrow.down.doc" : nil)
            }
        } control: {
            if repository[event] != nil {
                Button("Show…") { editing = .init(event: event, scope: .repository(project: projectRoot)) }
            } else {
                Button(settings.project(at: projectRoot).scripts[event] == nil ? "Add…" : "Edit…") {
                    editing = .init(event: event, scope: .project(projectRoot))
                }
            }
        }
        .settingsManaged(by: repository[event] == nil ? .taskScriptsUser : .taskScriptsRepository)
    }

    private func reload() {
        repository = settings.repositoryScripts(at: projectRoot)
    }

    /// Where the project's script for the event comes from; nil when it has none of its own.
    private func source(of event: TaskScriptEvent) -> TaskScript.Source? {
        if repository[event] != nil { return .repository }
        if settings.project(at: projectRoot).scripts[event] != nil { return .project }
        return settings.script(for: event).isEmpty ? nil : .global
    }

    private var repositoryDescription: String {
        let files = TaskScriptEvent.allCases.filter { repository[$0] != nil }.map(\.repositoryPath)
        let found =
            files.isEmpty
            ? "This repository has no .native scripts yet."
            : "This repository has \(files.formatted(.list(type: .and)))."
        return
            "\(found) Whoever commits to the repository can change them, so they don't run until you allow them here."
    }

    private func effect(of event: TaskScriptEvent, source: TaskScript.Source?) -> String {
        let project = settings.project(at: projectRoot)
        let combination = project.combination(for: event)
        let withGlobal =
            combination == .insteadOfGlobal || settings.script(for: event).isEmpty
            ? "" : ", after the global script"
        switch source {
        case .repository where !settings.allowsRepositoryScripts(forProjectAt: projectRoot):
            return "\(event.repositoryPath) waits until you allow the repo's scripts."
        case .repository:
            return "Runs \(event.repositoryPath)\(withGlobal)."
        case .project:
            return "Runs this project's script\(withGlobal)."
        case .global where combination == .insteadOfGlobal, nil where combination == .insteadOfGlobal:
            return "Nothing runs: the global script is off for this project."
        case .global:
            return "Runs the global script."
        case nil:
            return "Nothing runs."
        }
    }
}

#if NATIVE_PREVIEWS_WIP
#Preview("Project scripts") {
    DSPreviewPair {
        ProjectScriptsSection(projectRoot: TaskScriptsPreviewFixtures.project)
            .settingsPreviewPage()
    }
    .environment(TaskScriptsPreviewFixtures.settings())
}
#endif
