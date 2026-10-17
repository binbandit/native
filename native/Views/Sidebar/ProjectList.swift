import SwiftUI

/// The projects and their sessions (Conductor's sidebar tree): a "Projects" header with an add
/// button, then each project as a collapsible group in the user's order. Collapsed projects are
/// remembered, and a project expands when one of its sessions is selected.
struct ProjectList<TaskAccessory: View>: View {
    @Environment(AppModel.self) private var model
    let taskAccessory: (SessionSummary) -> TaskAccessory
    let select: (SessionKey) -> Void

    @AppStorage(CollapsedProjects.storageKey) private var collapsed = CollapsedProjects()
    @State private var drag = SidebarDragState()

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.xxs) {
            SectionHeader("Projects") {
                IconButton("Add Project", systemImage: "folder.badge.plus") {
                    model.isAddingProject = true
                }
            }
            // Lines the button up with the projects' "+" buttons.
            .padding(.trailing, DS.Space.sm)
            if model.projects.all.isEmpty {
                AddProjectPrompt()
            }
            ForEach(model.projects.all) { project in
                ProjectSection(
                    project: project,
                    isExpanded: Binding(
                        get: { !collapsed.contains(project.id) },
                        set: { collapsed.set(project.id, collapsed: !$0) }
                    ),
                    drag: drag,
                    taskAccessory: taskAccessory,
                    select: select
                )
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
}

/// Conductor's empty tree: a dashed button to add the first project.
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
                .frame(maxWidth: .infinity, alignment: .leading)
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
