import ProjectActions
import SwiftUI

/// The Actions part of a project's settings page: the user's own actions (add, edit, reorder,
/// delete, with undo), the repo's from `.native/actions.json`, and what Native suggests from the
/// project's files, each one click to add or dismiss.
///
///     ProjectActionsSettingsSection(project: project)
struct ProjectActionsSettingsSection: View {
    let project: Project

    @Environment(ProjectActionRunner.self) private var runner
    @Environment(AppModel.self) private var model
    @Environment(\.undoManager) private var undoManager
    @State private var editing: ProjectActionEditor.Subject?
    @State private var showsAllSuggestions = false
    @State private var didCopyFile = false

    /// Where search reveals the section on the project's page.
    static func row(_ project: Project.ID) -> SettingsRowID {
        SettingsRowID("project.\(project.uuidString).actions")
    }

    /// For the page's `searchEntries`.
    static func searchEntry(_ project: Project.ID) -> SettingsSearchEntry {
        SettingsSearchEntry(
            id: row(project), title: "Actions",
            keywords: ["run", "script", "test", "install", "build", "command", "justfile", "package.json"])
    }

    /// Suggestions shown before "Show More".
    private static let suggestionPreview = 6

    private var store: ProjectActionStore { runner.store }

    var body: some View {
        let list = store.list(for: project)
        VStack(alignment: .leading, spacing: DS.Space.lg) {
            SettingsSubheading(
                "Actions",
                note: "Commands you run from a task's Run menu, in the task's worktree. Give one a shortcut in "
                    + "Keyboard Shortcuts."
            )
            .settingsRevealTarget(Self.row(project.id))
            SettingsRowGroup {
                ForEach(Array(list.yours.enumerated()), id: \.element.id) { index, action in
                    ProjectActionSettingsRow(action: action) {
                        Button("Edit…") { editing = .existing(action) }
                        ProjectActionRowMenu(
                            name: action.name,
                            canMoveUp: index > 0,
                            canMoveDown: index < list.yours.count - 1,
                            move: { store.move(action.id, by: $0, in: project) },
                            delete: { delete(action) }
                        )
                    }
                }
                SettingsRow(
                    list.yours.isEmpty ? "No actions yet" : "Another action",
                    description: Text("A name and a command, like Test for \(exampleCommand(list)).")
                ) {
                    Button("Add Action…") { editing = .new }
                }
            }
            repository(list)
            suggestions(list)
        }
        .task(id: project.id) {
            store.refresh(project)
            if store.requestedNewAction == project.id {
                store.requestedNewAction = nil
                editing = .new
            }
        }
        .sheet(item: $editing) { subject in
            ProjectActionEditor(project: project, subject: subject)
        }
    }

    // MARK: From the repo

    @ViewBuilder private func repository(_ list: ProjectActionList) -> some View {
        if list.isRepositoryOff {
            SettingsNote("Actions from the repo are off", systemImage: "lock") {
                Text("Your organization doesn't let repo files supply commands, so .native/actions.json isn't read.")
            }
        } else {
            switch list.repositoryFile {
            case .none:
                SettingsRowGroup {
                    SettingsRow(
                        "Share actions with your team",
                        description: Text(
                            "Commit them as \(ProjectActionFile.path) and everyone who opens the repo gets them.")
                    ) {
                        Button(didCopyFile ? "Copied" : "Copy as JSON") { copyFile(list.yours) }
                            .disabled(list.yours.isEmpty)
                    }
                }
            case .unreadable(let reason):
                NoticeBanner(
                    tone: .warning, title: "The repo's actions didn't load", detail: reason,
                    footnote: "Your own actions still work. Fix the file and Native reads it again."
                ) {
                    Button("Reload") { store.refresh(project) }
                        .buttonStyle(.ds(.secondary))
                }
            case .actions(let actions, let skipped):
                SettingsSubheading(
                    "From the repo",
                    note: "From \(ProjectActionFile.path), shared with everyone who works on the repo. Edit the file to "
                        + "change them."
                )
                SettingsRowGroup {
                    ForEach(actions) { action in
                        ProjectActionSettingsRow(action: action) {
                            Button("Copy to Mine") { store.add(copy(of: action, among: list.all), to: project) }
                        }
                    }
                }
                if !skipped.isEmpty {
                    SettingsNote("Some entries were skipped", systemImage: "exclamationmark.triangle") {
                        Text(skipped.joined(separator: "\n"))
                    }
                }
            }
        }
    }

    // MARK: Suggested

    @ViewBuilder private func suggestions(_ list: ProjectActionList) -> some View {
        let dismissedCount = store.dismissedCount(in: project)
        if !list.suggestions.isEmpty || dismissedCount > 0 {
            SettingsSubheading(
                "Suggested",
                note: "Found in \(sources(of: list.suggestions)). Nothing runs until you add it and run it."
            )
            SettingsRowGroup {
                let shown = showsAllSuggestions ? list.suggestions : Array(list.suggestions.prefix(Self.suggestionPreview))
                ForEach(shown) { suggestion in
                    SettingsRow(
                        suggestion.name,
                        icon: suggestion.icon,
                        description: Text(suggestion.command).font(.dsMono),
                        detail: Text(detail(of: suggestion))
                    ) {
                        HStack(spacing: DS.Space.sm) {
                            Button("Dismiss") { dismiss(suggestion) }
                                .buttonStyle(.ds(.ghost))
                            Button("Add") { store.add(suggestion, to: project) }
                        }
                    }
                }
                if list.suggestions.count > Self.suggestionPreview {
                    SettingsRow(
                        showsAllSuggestions ? "Showing all \(list.suggestions.count)" : "\(list.suggestions.count - Self.suggestionPreview) more",
                        description: Text("Every script, recipe and target Native found.")
                    ) {
                        Button(showsAllSuggestions ? "Show Fewer" : "Show All") { showsAllSuggestions.toggle() }
                    }
                }
                if dismissedCount > 0 {
                    SettingsRow(
                        dismissedCount == 1 ? "1 dismissed suggestion" : "\(dismissedCount) dismissed suggestions",
                        description: Text("Bring them back to add one after all.")
                    ) {
                        Button("Show Again") { store.undismissAll(in: project) }
                    }
                }
            }
        } else if list.hasScanned, list.all.isEmpty {
            SettingsNote("Nothing to suggest yet", systemImage: "sparkle.magnifyingglass") {
                Text(
                    "Native suggests actions from a package.json, justfile, Makefile, Cargo.toml, Package.swift, "
                        + "go.mod, pyproject.toml, Gradle, Maven or Compose file at the project's top level."
                )
            }
        }
    }

    // MARK: Helpers

    private func detail(of suggestion: ProjectSuggestion) -> String {
        let from = "From \(suggestion.source.title)"
        guard let detail = suggestion.detail, !detail.isEmpty, detail != suggestion.command else { return from }
        return "\(from) · \(detail)"
    }

    /// "package.json, justfile and Cargo.toml".
    private func sources(of suggestions: [ProjectSuggestion]) -> String {
        var seen: Set<ProjectSuggestion.Source> = []
        let titles = suggestions.map(\.source).filter { seen.insert($0).inserted }.map(\.title)
        return titles.isEmpty ? "the project's files" : titles.formatted(.list(type: .and))
    }

    private func exampleCommand(_ list: ProjectActionList) -> String {
        list.suggestions.first { $0.role == .test }?.command ?? "npm test"
    }

    private func copy(of action: ProjectAction, among existing: [ProjectAction]) -> ProjectAction {
        var copy = action
        copy.id = .yours()
        copy.name = ProjectAction.uniqueName(action.name, among: existing)
        return copy
    }

    private func copyFile(_ actions: [ProjectAction]) {
        guard let data = try? ProjectActionFile.encode(actions) else { return }
        DSPasteboard.copy(String(decoding: data, as: UTF8.self))
        didCopyFile = true
        Task {
            try? await Task.sleep(for: .seconds(2))
            didCopyFile = false
        }
    }

    /// Deletes at once, with Undo in the toast and on ⌘Z.
    private func delete(_ action: ProjectAction) {
        guard let removed = store.remove(action.id, from: project) else { return }
        let project = project
        let store = store
        let undo = { store.restore(removed.action, at: removed.index, in: project) }
        undoManager?.registerUndo(withTarget: store) { _ in MainActor.assumeIsolated { undo() } }
        undoManager?.setActionName("Delete Action")
        model.lastUndoable = UndoableAction(message: "Deleted “\(action.name)”", undo: undo)
    }

    private func dismiss(_ suggestion: ProjectSuggestion) {
        store.dismiss(suggestion, in: project)
        let project = project
        let store = store
        let undo = { store.undismiss(suggestion, in: project) }
        undoManager?.registerUndo(withTarget: store) { _ in MainActor.assumeIsolated { undo() } }
        undoManager?.setActionName("Dismiss Suggestion")
        model.lastUndoable = UndoableAction(message: "Dismissed “\(suggestion.name)”", undo: undo)
    }
}
