import ProjectActions
import SwiftUI

/// Adds or edits one of the user's actions, as a sheet: its name, command, folder, where its
/// output goes, and its icon. ⌘Return saves.
struct ProjectActionEditor: View {
    /// What the sheet edits.
    enum Subject: Identifiable {
        case new
        case existing(ProjectAction)

        var id: String {
            switch self {
            case .new: "new"
            case .existing(let action): action.id.rawValue
            }
        }
    }

    let project: Project
    let subject: Subject

    @Environment(ProjectActionRunner.self) private var runner
    @Environment(\.dismiss) private var dismiss
    @State private var draft: ProjectAction

    /// Glyphs to pick from: the suggestions' and a few more for common jobs.
    private static let icons = [
        "terminal", "play", "play.circle", "checkmark.seal", "hammer", "arrow.down.circle", "checklist",
        "checkmark.shield", "text.alignleft", "wand.and.stars", "shippingbox", "stop.circle", "arrow.clockwise",
        "bolt", "ladybug", "doc.text", "server.rack", "globe",
    ]

    init(project: Project, subject: Subject) {
        self.project = project
        self.subject = subject
        switch subject {
        case .new: _draft = State(initialValue: ProjectAction(name: "", command: ""))
        case .existing(let action): _draft = State(initialValue: action)
        }
    }

    private var isNew: Bool {
        if case .new = subject { true } else { false }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.xl) {
            VStack(alignment: .leading, spacing: DS.Space.xs) {
                Text(isNew ? "New Action for \(project.name)" : "Edit “\(nameOnOpen)”")
                    .font(.dsHeadline)
                    .foregroundStyle(.dsTextPrimary)
                Text(
                    "Runs with your shell in the task's worktree, from the Run menu, the command palette and the "
                        + "project's menu. NATIVE_PROJECT_PATH, NATIVE_WORKTREE_PATH and NATIVE_ACTION are set."
                )
                .font(.dsBody)
                .foregroundStyle(.dsTextSecondary)
                .fixedSize(horizontal: false, vertical: true)
            }
            field("Name") {
                TextField("Test", text: $draft.name)
                    .settingsField()
            }
            field("Command") {
                TextField("bun run test", text: $draft.command, axis: .vertical)
                    .font(.dsMono)
                    .lineLimit(1...4)
                    .settingsField()
            }
            field("Folder") {
                HStack(spacing: DS.Space.sm) {
                    SettingsSelect(
                        label: "Folder", selection: $draft.directory.base,
                        options: [
                            .init(value: .worktree, title: "Task's worktree"),
                            .init(value: .project, title: "Project's folder"),
                        ])
                    TextField("Top level", text: $draft.directory.path)
                        .font(.dsMono)
                        .settingsField()
                }
            }
            field("Output") {
                SettingsSelect(
                    label: "Output", selection: $draft.presentation,
                    options: [
                        .init(value: .terminal, title: "In a terminal tab"),
                        .init(value: .background, title: "In the background, with a toast"),
                    ],
                    width: ProjectActionMetrics.editorWidth / 2)
            }
            field("Icon") {
                FlowLayout(spacing: DS.Space.xs) {
                    ForEach(Self.icons, id: \.self) { icon in
                        IconButton(icon, systemImage: icon, size: .medium, isActive: selectedIcon == icon) {
                            draft.icon = icon
                        }
                        .accessibilityAddTraits(selectedIcon == icon ? .isSelected : [])
                    }
                }
            }
            HStack(spacing: DS.Space.md) {
                if let problem {
                    Text(problem)
                        .font(.dsBody)
                        .foregroundStyle(.dsDanger)
                }
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                    .buttonStyle(.ds(.secondary))
                    .keyboardShortcut(.cancelAction)
                Button(isNew ? "Add Action" : "Save") { save() }
                    .buttonStyle(.ds(.primary))
                    .keyboardShortcut(.return, modifiers: .command)
                    .disabled(problem != nil)
            }
        }
        .padding(DS.Space.xl)
        .frame(width: ProjectActionMetrics.editorWidth)
    }

    private func field(_ title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: DS.Space.sm) {
            Text(title)
                .font(.dsBodyMedium)
                .foregroundStyle(.dsTextPrimary)
            content()
        }
    }

    private var nameOnOpen: String {
        if case .existing(let action) = subject { action.name } else { "" }
    }

    private var selectedIcon: String {
        draft.icon ?? ProjectActionGlyph.fallback
    }

    /// Why it can't be saved yet, in a few words; nil when it can.
    private var problem: String? {
        let name = draft.name.trimmingCharacters(in: .whitespacesAndNewlines)
        if name.isEmpty { return "Give it a name." }
        if draft.command.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return "Give it a command." }
        let others = runner.store.list(for: project).all.filter { $0.id != draft.id }
        if let key = ProjectAction.key(forName: name), others.contains(where: { $0.key == key }) {
            return "Another action is called \(name)."
        }
        return nil
    }

    private func save() {
        guard problem == nil else { return }
        var action = draft
        action.name = action.name.trimmingCharacters(in: .whitespacesAndNewlines)
        action.command = action.command.trimmingCharacters(in: .whitespacesAndNewlines)
        action.directory.path = action.directory.path.trimmingCharacters(in: .whitespaces)
        if isNew {
            runner.store.add(action, to: project)
        } else {
            runner.store.update(action, in: project)
        }
        dismiss()
    }
}
