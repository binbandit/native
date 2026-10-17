import SwiftUI

/// The projects and their sessions (the reference app's sidebar tree): a "Projects" header with the Needs You
/// filter and an add button, each project as a collapsible group in the user's order, then what's
/// archived. Collapsed projects are remembered, and a project expands when one of its sessions is
/// selected.
struct ProjectList<TaskAccessory: View>: View {
    @Environment(AppModel.self) private var model
    let taskAccessory: (SessionSummary) -> TaskAccessory
    @Binding var showsOnlyNeedsYou: Bool
    let select: (SessionKey) -> Void

    @AppStorage(CollapsedProjects.storageKey) private var collapsed = CollapsedProjects()
    @State private var drag = SidebarDragState()

    var body: some View {
        let groups = model.projects.all.map { project in (project, visibleSessions(in: project.id)) }
        VStack(alignment: .leading, spacing: DS.Space.xxs) {
            SectionHeader(showsOnlyNeedsYou ? "Needs You" : "Projects") {
                IconButton(
                    showsOnlyNeedsYou ? "Show All Tasks (⌥⌘J)" : "Show Only Tasks That Need You (⌥⌘J)",
                    systemImage: "line.3.horizontal.decrease",
                    isActive: showsOnlyNeedsYou
                ) {
                    showsOnlyNeedsYou.toggle()
                }
                IconButton("Add Project", systemImage: "folder.badge.plus") {
                    model.isAddingProject = true
                }
            }
            // Lines the buttons up with the projects' "+" buttons.
            .padding(.trailing, DS.Space.sm)

            if model.projects.all.isEmpty {
                AddProjectPrompt()
            } else if showsOnlyNeedsYou, groups.allSatisfy({ $0.1.isEmpty }) {
                NothingNeedsYou { showsOnlyNeedsYou = false }
            }
            ForEach(groups, id: \.0.id) { project, sessions in
                if !showsOnlyNeedsYou || !sessions.isEmpty {
                    ProjectSection(
                        project: project,
                        sessions: sessions,
                        isFiltered: showsOnlyNeedsYou,
                        isExpanded: Binding(
                            get: { showsOnlyNeedsYou || !collapsed.contains(project.id) },
                            set: { collapsed.set(project.id, collapsed: !$0) }
                        ),
                        drag: drag,
                        taskAccessory: taskAccessory,
                        select: select
                    )
                }
            }
            if !showsOnlyNeedsYou {
                ArchivedSection(select: select)
            }
        }
        .onChange(of: model.selection) {
            guard let selection = model.selection,
                let project = model.sessionList.first(where: { $0.id == selection })?.project,
                collapsed.contains(project)
            else { return }
            withAnimation(.dsDisclosure) {
                collapsed.set(project, collapsed: false)
            }
        }
    }

    /// A project's sessions as the list shows them: all of them, or with the filter on, only those
    /// waiting on the user (asking for something, or finished while they looked elsewhere).
    private func visibleSessions(in project: Project.ID) -> [SessionSummary] {
        let sessions = model.sessions(in: project)
        guard showsOnlyNeedsYou else { return sessions }
        return sessions.filter { TaskStatus(model.session($0.id)).needsAttention || model.isUnread($0.id) }
    }
}

/// the reference app's empty tree: a dashed button to add the first project.
private struct AddProjectPrompt: View {
    @Environment(AppModel.self) private var model
    @State private var isHovered = false

    var body: some View {
        Button {
            model.isAddingProject = true
        } label: {
            Label("Add Project", systemImage: "plus")
                .font(.dsCallout)
                .foregroundStyle(isHovered ? .dsTextPrimary : .dsTextSecondary)
                .padding(.horizontal, DS.Space.md)
                .padding(.vertical, DS.Space.sm)
                .frame(maxWidth: .infinity, minHeight: DS.Size.minimumHitTarget, alignment: .leading)
                .contentShape(.rect)
                .overlay {
                    RoundedRectangle(cornerRadius: DS.Radius.row, style: .continuous)
                        .strokeBorder(
                            .dsSeparator, style: StrokeStyle(lineWidth: 1, dash: [DS.Space.xs, DS.Space.xxs]))
                }
        }
        .buttonStyle(SidebarRowButtonStyle())
        .trackHover($isHovered)
        .help("Add a project folder (⌘O)")
        .padding(.vertical, DS.Space.xs)
    }
}

/// The Needs You filter with nothing to show: say so, and offer the way back.
private struct NothingNeedsYou: View {
    let showAll: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.sm) {
            Text("Nothing needs you right now. Tasks show up here when they ask for something or finish.")
                .font(.dsBody)
                .foregroundStyle(.dsTextTertiary)
                .fixedSize(horizontal: false, vertical: true)
            Button("Show All Tasks", action: showAll)
                .buttonStyle(.ds(.secondary))
        }
        .padding(.horizontal, DS.Space.sm)
        .padding(.vertical, DS.Space.md)
    }
}
