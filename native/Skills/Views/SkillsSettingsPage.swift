#if canImport(Skills)
import Skills
import SwiftUI

extension SettingsPane.ID {
    static let skills = Self("skills")
}

extension SettingsPane {
    /// Settings ▸ Skills: every skill the agents load, one switch each, and installing new ones.
    static func skills(registry: PluginRegistry) -> SettingsPane {
        SettingsPane(
            id: .skills,
            title: "Skills",
            systemImage: "book.closed",
            group: .extensions,
            order: 25,
            keywords: ["skill", "SKILL.md", "skills.sh", "install", ".claude/skills", ".agents/skills", "codex"],
            searchEntries: {
                (SkillsPlugin.library(in: registry)?.items ?? []).map {
                    SettingsSearchEntry(
                        id: SkillsSettingsPage.rowID($0.key), title: $0.name, description: $0.description ?? "")
                }
            },
            content: { SkillsSettingsPage() }
        )
    }
}

/// What the page tells the user it just did, with a way back.
enum SkillsUndoNotice: Identifiable {
    case installed(SkillInstallRecord, agents: String)
    case removed(String, [SkillTrashEntry])
    case updated(String, [SkillTrashEntry])

    var id: String {
        switch self {
        case .installed(let record, _): "installed-\(record.id)"
        case .removed(let name, _): "removed-\(name)"
        case .updated(let name, _): "updated-\(name)"
        }
    }

    var text: String {
        switch self {
        case .installed(let record, let agents): "Installed \(record.name) for \(agents)."
        case .removed(let name, _): "Removed \(name). Native kept it in its trash."
        case .updated(let name, _): "Updated \(name). Native kept the old version in its trash."
        }
    }
}

struct SkillsSettingsPage: View {
    @Environment(PluginRegistry.self) private var registry
    @Environment(\.undoManager) private var undoManager
    @State private var projectPath = ""
    @State private var filter = ""
    @State private var expanded: Set<String> = []
    @State private var isInstalling = false
    @State private var updating: SkillItem?
    @State private var removing: SkillItem?
    @State private var notice: SkillsUndoNotice?

    static func rowID(_ key: String) -> SettingsRowID {
        SettingsRowID("skills.\(key)")
    }

    private var project: URL? {
        projectPath.isEmpty ? nil : URL(filePath: projectPath, directoryHint: .isDirectory)
    }

    var body: some View {
        if let library = SkillsPlugin.library(in: registry) {
            page(library)
        } else {
            EmptyStateView(
                "Skills aren't available", systemImage: "book.closed",
                message: "The Skills plugin isn't loaded in this build.")
        }
    }

    private func page(_ library: SkillLibrary) -> some View {
        SettingsPage {
            SettingsHeader(
                title: "Skills",
                description: Text(
                    "Skills teach agents one kind of work. Turn one off and Native leaves it out of every agent's new sessions, without touching its files."
                )
            ) {
                Button("Install Skill", systemImage: "plus") { isInstalling = true }
                    .buttonStyle(.ds(.primary, size: .medium))
                    .disabled(library.agents.isEmpty)
            }
            notices(library)
            if library.agents.isEmpty {
                MCPEmptyRow(
                    title: "No agents that load skills",
                    message:
                        "Claude Code, Codex, Cursor, OpenCode, Pi and Copilot keep skills. Turn one on in Agents to see and switch its skills here."
                )
            } else {
                toolbar(library)
                SkillsSections(
                    library: library, project: project, filter: filter, expanded: $expanded,
                    onInstall: { isInstalling = true }, onUpdate: { updating = $0 }, onRemove: { removing = $0 },
                    onToggle: { item, isOn in toggle(item.key, name: item.name, isOn: isOn, in: library) },
                    onToggleNative: { skill, isOn in
                        toggle(SkillItem.key(for: skill.id), name: skill.title, isOn: isOn, in: library)
                    }
                )
                SkillFoldersSection(library: library, project: project)
            }
        }
        .task { if library.lastRead == nil || library.items.isEmpty { await library.read() } }
        .sheet(isPresented: $isInstalling) {
            SkillInstallSheet(library: library, project: project) { record, agents in
                show(.installed(record, agents: agents))
            }
        }
        .sheet(item: $updating) { item in
            SkillUpdateSheet(library: library, item: item) { entries in show(.updated(item.name, entries)) }
        }
        .confirmationDialog(
            removing.map { "Remove \($0.name)?" } ?? "", isPresented: isRemovingBinding, titleVisibility: .visible,
            presenting: removing
        ) { item in
            Button("Remove", role: .destructive) { Task { await remove(item, from: library) } }
        } message: { item in
            Text(SkillsRemoval.message(for: item, home: library.home))
        }
    }

    @ViewBuilder
    private func notices(_ library: SkillLibrary) -> some View {
        if !registry.isEnabled(SkillsPlugin.id) {
            MCPNotice(
                text:
                    "The Skills plugin is off, so switches here don't reach agents. Turn it on in Settings ▸ Extensions.",
                tone: .warning)
        }
        if let problem = library.problem {
            MCPNotice(text: problem, tone: .danger, actionTitle: "Dismiss") { library.problem = nil }
        }
        let waiting = library.host?.skillAgentsAwaitingRestart ?? []
        if !waiting.isEmpty {
            MCPNotice(
                text:
                    "\(waiting.map(\.name).joined(separator: " and ")) applies skill switches when it starts, so it restarts as soon as none of its sessions is working.",
                tone: .neutral, actionTitle: "Apply to Running Sessions"
            ) {
                Task { await library.host?.skillApplyLaunchPolicies(force: true) }
            }
        }
        if let notice {
            MCPNotice(text: notice.text, tone: .neutral, actionTitle: "Undo") {
                Task { await undo(notice, in: library) }
            }
        }
    }

    private func toolbar(_ library: SkillLibrary) -> some View {
        HStack(spacing: DS.Space.md) {
            SearchField("Filter skills", text: $filter, size: .large, font: SettingsTextStyle.body.font)
                .frame(maxWidth: 260)
            Spacer(minLength: DS.Space.xl)
            SettingsSelect(
                label: "Switches apply to", selection: $projectPath, options: projectOptions(library), width: 200)
            IconButton("Read Again", systemImage: "arrow.clockwise") { Task { await library.read() } }
                .disabled(library.isReading)
                .help("Read every agent's skills folders again")
        }
    }

    private func projectOptions(_ library: SkillLibrary) -> [SettingsSelect<String>.Option] {
        [SettingsSelect<String>.Option(value: "", title: "All Projects")]
            + (library.host?.skillProjects ?? []).map {
                SettingsSelect<String>.Option(value: SkillPaths.key($0), title: $0.lastPathComponent)
            }
    }

    private var isRemovingBinding: Binding<Bool> {
        Binding(get: { removing != nil }, set: { if !$0 { removing = nil } })
    }

    // MARK: - Actions

    /// Sets the switch where the page points (all projects, or one), and makes it undoable. A
    /// project switch that matches the global one is cleared, so the project follows it again.
    private func toggle(_ key: String, name: String, isOn: Bool, in library: SkillLibrary) {
        let mode: SkillSwitches.Mode = isOn ? .on : .off
        let target: SkillSwitches.Mode? = project != nil && library.mode(of: key, in: nil) == mode ? nil : mode
        let previous = library.setMode(project == nil && mode == .on ? nil : target, for: key, in: project)
        let project = project
        undoManager?.registerUndo(withTarget: library) { library in
            library.setMode(previous, for: key, in: project)
        }
        undoManager?.setActionName(isOn ? "Turn On \(name)" : "Turn Off \(name)")
    }

    private func remove(_ item: SkillItem, from library: SkillLibrary) async {
        do {
            let entries = try await library.remove(SkillsRemoval.paths(of: item))
            show(.removed(item.name, entries))
        } catch {
            library.problem = error.localizedDescription
        }
    }

    private func show(_ notice: SkillsUndoNotice) {
        withAnimation(.dsStandard) { self.notice = notice }
    }

    private func undo(_ notice: SkillsUndoNotice, in library: SkillLibrary) async {
        switch notice {
        case .installed(let record, _): await library.undoInstall(record)
        case .removed(_, let entries), .updated(_, let entries): await library.restore(entries)
        }
        withAnimation(.dsStandard) { self.notice = nil }
    }
}

/// What removing a skill touches: every copy Native may manage, and links rather than what they
/// point to.
enum SkillsRemoval {
    static func paths(of item: SkillItem) -> [String] {
        item.places.filter { $0.root.scope.isUserManaged }.map(\.path)
    }

    static func message(for item: SkillItem, home: String) -> String {
        let lines = item.places.filter { $0.root.scope.isUserManaged }.map { place in
            SkillPaths.abbreviated(place.path, home: home) + (place.isLink ? " (a link; what it points to stays)" : "")
        }
        return "Native moves \(lines.joined(separator: ", ")) to its trash, so no agent loads it. You can undo this."
    }
}
#endif
