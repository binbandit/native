import SwiftUI
import TaskScripts

/// Edits one event's script, global or a project's, or shows the one a repository commits: a
/// monospace editor, for a project whether it runs after the global script or instead of it, for a
/// global script its time limit, the variables scripts get, and Run Test.
struct TaskScriptEditorSheet: View {
    /// Whose script for which event.
    struct Target: Identifiable, Hashable {
        enum Scope: Hashable {
            case global
            /// The project's own, kept on this Mac.
            case project(URL)
            /// The one the project's repository commits, which isn't edited here.
            case repository(project: URL)

            init(_ source: TaskScript.Source, project: URL) {
                switch source {
                case .global: self = .global
                case .project: self = .project(project)
                case .repository: self = .repository(project: project)
                }
            }

            var project: URL? {
                switch self {
                case .global: nil
                case .project(let project), .repository(let project): project
                }
            }
        }

        let event: TaskScriptEvent
        let scope: Scope

        var id: Self { self }
    }

    let target: Target

    @Environment(TaskScriptSettings.self) private var settings
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @State private var repositoryText: String?
    @State private var showsVariables = false

    private var event: TaskScriptEvent { target.event }

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.xl) {
            header
            if case .project(let project) = target.scope {
                combination(project)
                if repositoryText != nil {
                    Text(
                        "The repository's \(event.repositoryPath) takes the place of this script while the project allows its repository's scripts."
                    )
                    .settingsText(.caption)
                    .foregroundStyle(.dsTextSecondary)
                }
            }
            editor
            if target.scope == .global {
                timeout
            }
            variables
            TaskScriptTestPanel(text: isRepository ? (repositoryText ?? "") : text, target: target)
            footer
        }
        .padding(DS.Space.xxl)
        .frame(width: TaskScriptMetrics.editorSheetWidth)
        .background(.dsBackground)
        .onAppear(perform: load)
    }

    private var isRepository: Bool {
        if case .repository = target.scope { true } else { false }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: DS.Space.md) {
            Text(title)
                .settingsText(.title)
                .foregroundStyle(.dsTextPrimary)
            Text(event.summary)
                .settingsText(.body)
                .foregroundStyle(.dsTextSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var title: String {
        switch target.scope {
        case .global: "\(event.title) script for every project"
        case .project(let project): "\(event.title) script for \(project.lastPathComponent)"
        case .repository(let project): "\(project.lastPathComponent)'s \(event.repositoryPath)"
        }
    }

    private func combination(_ project: URL) -> some View {
        Picker(
            "Runs",
            selection: Binding(
                get: { settings.project(at: project).combination(for: event) },
                set: { settings.setCombination($0, for: event, at: project) })
        ) {
            Text("After the global script").tag(ProjectTaskScripts.Combination.afterGlobal)
            Text("Instead of the global script").tag(ProjectTaskScripts.Combination.insteadOfGlobal)
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .fixedSize()
        .accessibilityLabel("When this project's script runs")
    }

    @ViewBuilder private var editor: some View {
        let shape = RoundedRectangle(cornerRadius: DS.Radius.control, style: .continuous)
        if isRepository {
            VStack(alignment: .leading, spacing: DS.Space.xs) {
                CappedHeightScrollView(maxHeight: TaskScriptMetrics.logOutputMaxHeight) {
                    Text(verbatim: repositoryText ?? "This repository doesn't have \(event.repositoryPath) anymore.")
                        .codeTextStyle()
                        .foregroundStyle(.dsTextPrimary)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(DS.Space.sm)
                }
                .background(.dsSurfaceSunken, in: shape)
                Text("Native runs this file from the project's main checkout. To change it, edit it in the repository.")
                    .settingsText(.caption)
                    .foregroundStyle(.dsTextSecondary)
            }
        } else {
            TextEditor(text: $text)
                .codeTextStyle()
                .scrollContentBackground(.hidden)
                .padding(DS.Space.sm)
                .frame(minHeight: TaskScriptMetrics.editorMinHeight)
                .background(.dsSurface, in: shape)
                .overlay { shape.strokeBorder(.dsBorder, lineWidth: 1) }
                .accessibilityLabel("\(event.title) script")
        }
    }

    private var timeout: some View {
        HStack(spacing: DS.Space.md) {
            Text("Stop it after")
                .settingsText(.body)
                .foregroundStyle(.dsTextSecondary)
            SettingsSelect(
                label: "Stop it after",
                selection: Binding(get: { settings.timeout(for: event) }, set: { settings.setTimeout($0, for: event) }),
                options: TaskScriptTimeouts.choices.map { .init(value: $0, title: TaskScriptTimeouts.title($0)) })
            Spacer()
        }
    }

    private var variables: some View {
        DisclosureGroup("Environment variables", isExpanded: $showsVariables) {
            TaskScriptVariablesList()
                .padding(.top, DS.Space.sm)
        }
        .settingsText(.body)
        .foregroundStyle(.dsTextSecondary)
    }

    private var footer: some View {
        HStack(spacing: DS.Space.md) {
            Spacer()
            if isRepository {
                Button("Done") { dismiss() }
                    .buttonStyle(.ds(.primary, size: .large))
                    .keyboardShortcut(.defaultAction)
            } else {
                Button("Cancel", role: .cancel) { dismiss() }
                    .buttonStyle(.ds(.secondary, size: .large))
                    .keyboardShortcut(.cancelAction)
                Button("Save") {
                    save()
                    dismiss()
                }
                .buttonStyle(.ds(.primary, size: .large))
                .keyboardShortcut(.return, modifiers: .command)
            }
        }
    }

    private func load() {
        switch target.scope {
        case .global:
            text = settings.script(for: event)
        case .project(let project):
            text = settings.project(at: project).scripts[event] ?? ""
            repositoryText = settings.repositoryScripts(at: project)[event]
        case .repository(let project):
            repositoryText = settings.repositoryScripts(at: project)[event]
        }
    }

    private func save() {
        switch target.scope {
        case .global: settings.setScript(text, for: event)
        case .project(let project): settings.setProjectScript(text, for: event, at: project)
        case .repository: break
        }
    }
}

/// The `NATIVE_*` variables every script gets, with what each holds.
struct TaskScriptVariablesList: View {
    var body: some View {
        Grid(alignment: .leading, horizontalSpacing: DS.Space.lg, verticalSpacing: DS.Space.xs) {
            ForEach(TaskScriptVariables.all, id: \.name) { variable in
                GridRow {
                    Text(verbatim: variable.name)
                        .codeTextStyle(.compact)
                        .foregroundStyle(.dsTextPrimary)
                        .textSelection(.enabled)
                    Text(variable.meaning)
                        .settingsText(.caption)
                        .foregroundStyle(.dsTextSecondary)
                }
            }
        }
    }
}

#if NATIVE_PREVIEWS_WIP
#Preview("Script editor - Global setup") {
    DSPreviewPair {
        TaskScriptEditorSheet(target: TaskScriptEditorSheet.Target(event: .setup, scope: .global))
    }
    .environment(TaskScriptsPreviewFixtures.settings())
    .environment(TaskScriptsPreviewFixtures.center())
    .environment(AppModel.preview())
}

#Preview("Script editor - Project's turn finished") {
    DSPreviewPair {
        TaskScriptEditorSheet(
            target: TaskScriptEditorSheet.Target(
                event: .turnFinished, scope: .project(TaskScriptsPreviewFixtures.project)))
    }
    .environment(TaskScriptsPreviewFixtures.settings())
    .environment(TaskScriptsPreviewFixtures.center())
    .environment(AppModel.preview())
}

#Preview("Script variables") {
    DSPreviewPair {
        TaskScriptVariablesList()
            .frame(width: 520)
    }
}
#endif
