import Modes
import NativeCommands
import SwiftUI

extension SettingsPane.ID {
    static let modes = Self("modes")
}

extension SettingsRowID {
    static let modesDefault = Self("modes.default")
    static let modesYours = Self("modes.yours")
    static let modesProjects = Self("modes.projects")
}

extension SettingsPane {
    static func modes(projects: [Project]) -> SettingsPane {
        SettingsPane(
            id: .modes,
            title: "Modes",
            systemImage: "wand.and.stars",
            group: .agents,
            order: 26,
            keywords: ["plan", "ask", "debug", "review", "build", "instructions", "read-only", "custom mode"],
            searchEntries: {
                [
                    SettingsSearchEntry(
                        id: .modesDefault, title: "New tasks start in", keywords: ["default mode", "build"]),
                    SettingsSearchEntry(id: .modesYours, title: "Your modes", keywords: ["new mode", "custom"]),
                    SettingsSearchEntry(
                        id: .modesProjects, title: "Modes from projects", keywords: [".native/modes", "repository"]),
                ]
            },
            content: { ModesSettingsPage(projects: projects) }
        )
    }
}

/// Settings ▸ Modes: which mode new tasks start in, Native's own modes (each can be copied to make
/// one of the user's), the user's own (add, edit, delete with undo), and the modes open projects
/// share in their repositories, with any file that couldn't be used and why.
struct ModesSettingsPage: View {
    let projects: [Project]

    @Environment(\.undoManager) private var undoManager
    @State private var editing: ModeEditor.Subject?
    @State private var shownInstructions: Set<Mode.ID> = []
    private let library = ModeLibrary.shared

    var body: some View {
        SettingsPage {
            SettingsHeader(
                title: "Modes",
                description: Text(
                    "A mode is a way of working for a task: instructions Native gives the agent with your next message, and settings it applies as you pick it, such as keeping the agent read-only. Pick one from the Mode pill in the composer\(nextModeKey)."
                )
            ) {
                Button("New Mode…") { editing = .new }
                    .buttonStyle(.settings)
            }
            SettingsRowGroup {
                SettingsRow(
                    id: .modesDefault, "New tasks start in",
                    description: Text("Each task keeps its own mode after that, through restarts.")
                ) {
                    SettingsSelect(
                        label: "New tasks start in", selection: defaultMode,
                        options: (Mode.builtIn + library.custom).map { .init(value: $0.id, title: $0.name) })
                }
            }
            SettingsSubheading("Native's modes", note: "Built in. Duplicate one to make it your own.")
            SettingsRowGroup {
                ForEach(Mode.builtIn) { mode in
                    modeRow(mode) {
                        Button("Duplicate") { editing = .copy(mode) }
                            .disabled(mode.instructions.isEmpty)
                    }
                }
            }
            yours
            fromProjects
        }
        .sheet(item: $editing) { subject in
            ModeEditor(subject: subject)
        }
        .task {
            for project in projects {
                library.refresh(projectAt: project.url)
            }
        }
    }

    private var nextModeKey: String {
        CommandRegistry.shared.shortcut(for: .sessionNextMode).map { ", or press \($0.displayString) for the next" } ?? ""
    }

    private var defaultMode: Binding<Mode.ID> {
        Binding(get: { library.startingMode.id }, set: { library.defaultMode = $0 })
    }

    // MARK: Yours

    @ViewBuilder private var yours: some View {
        SettingsSubheading("Your modes", note: "Yours, in every project.")
            .settingsRevealTarget(.modesYours)
        if library.custom.isEmpty {
            EmptyStateView(
                "No modes of your own yet", systemImage: "wand.and.stars",
                message:
                    "Give the agent your own way of working, like a security review or writing docs, and pick it for any task."
            ) {
                Button("New Mode…") { editing = .new }
                    .buttonStyle(.ds(.secondary))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, DS.Space.xl)
        } else {
            SettingsRowGroup {
                ForEach(library.custom) { mode in
                    modeRow(mode) {
                        Button("Edit…") { editing = .existing(mode) }
                        ModeRowMenu(mode: mode) {
                            editing = .copy(mode)
                        } delete: {
                            library.remove(mode.id, undoManager: undoManager)
                        }
                    }
                }
            }
        }
    }

    // MARK: From projects

    @ViewBuilder private var fromProjects: some View {
        SettingsSubheading(
            "From projects",
            note:
                "A project shares modes by committing them as \(ModeFile.folder)/<name>.md: settings at the top, instructions below. A project's mode can make the agent more careful, never give it more freedom."
        )
        .settingsRevealTarget(.modesProjects)
        let sharing = projects.filter { project in
            let modes = library.projectModes(at: project.url)
            return !modes.modes.isEmpty || !modes.problems.isEmpty
        }
        if sharing.isEmpty {
            SettingsNote("No open project shares modes yet", systemImage: "folder") {
                Text(
                    "Copy one of your modes as a file (its … menu), save it in a project's \(ModeFile.folder) folder and commit it. Everyone who opens the project gets it."
                )
            }
        } else {
            ForEach(sharing) { project in
                VStack(alignment: .leading, spacing: DS.Space.md) {
                    Text(project.name)
                        .settingsText(.bodyMedium)
                        .foregroundStyle(.dsTextSecondary)
                    ProjectModesList(root: project.url) { mode in
                        editing = .copy(mode)
                    }
                }
            }
        }
    }

    // MARK: Rows

    private func modeRow(_ mode: Mode, @ViewBuilder controls: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: DS.Space.md) {
            SettingsRow(
                mode.name, icon: mode.symbol, description: Text(mode.summary),
                detail: Text(ModeSettingsText.describe(mode))
            ) {
                HStack(spacing: DS.Space.sm) {
                    if !mode.instructions.isEmpty {
                        Button(shownInstructions.contains(mode.id) ? "Hide Instructions" : "Instructions") {
                            shownInstructions.formSymmetricDifference([mode.id])
                        }
                    }
                    controls()
                }
            }
            if shownInstructions.contains(mode.id) {
                ModeInstructionsText(mode: mode)
            }
        }
    }
}

/// A mode's instructions as the agent gets them, under its row.
struct ModeInstructionsText: View {
    let mode: Mode

    var body: some View {
        Text(mode.instructions)
            .settingsText(.caption)
            .foregroundStyle(.dsTextSecondary)
            .textSelection(.enabled)
            .fixedSize(horizontal: false, vertical: true)
            .padding(DS.Space.lg)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.dsSurfaceSunken, in: .rect(cornerRadius: DS.Radius.card, style: .continuous))
    }
}

/// The "…" menu on one of the user's modes: duplicate it, copy it as a file to commit to a
/// project, or delete it (⌘Z brings it back).
struct ModeRowMenu: View {
    let mode: Mode
    let duplicate: () -> Void
    let delete: () -> Void

    var body: some View {
        Menu {
            Button("Duplicate", action: duplicate)
            Button("Copy as File") { DSPasteboard.copy(ModeFile.contents(of: mode)) }
                .help("Copies it as \(ModeFile.fileName(for: mode.name)), to commit in a project's \(ModeFile.folder) folder")
            Divider()
            Button("Delete", role: .destructive, action: delete)
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: SettingsMetrics.navGlyph, weight: .regular))
                .foregroundStyle(.dsTextSecondary)
                .frame(width: DS.Size.controlSM, height: DS.Size.controlSM)
                .contentShape(.rect)
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .accessibilityLabel("More for \(mode.name)")
    }
}
