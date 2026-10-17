import ACP
import SwiftUI

/// What the user archived, at the foot of the project list, collapsed until opened: archived
/// projects, then archived tasks, each with Unarchive and Delete. Archived tasks can still be
/// opened to read. Hidden when nothing is archived.
struct ArchivedSection: View {
    @Environment(AppModel.self) private var model
    let select: (SessionKey) -> Void

    @AppStorage("sidebar.showsArchived") private var isExpanded = false

    var body: some View {
        let projects = model.projects.archived
        let tasks = (model.projects.all + projects).flatMap { model.archivedSessions(in: $0.id) }
        if !projects.isEmpty || !tasks.isEmpty {
            VStack(alignment: .leading, spacing: DS.Space.xs) {
                Button {
                    withAnimation(.dsDisclosure) { isExpanded.toggle() }
                } label: {
                    SectionHeader("Archived") {
                        Text("\(projects.count + tasks.count)")
                            .font(.dsMonoCaption)
                            .foregroundStyle(.dsTextTertiary)
                        Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                            .font(.dsMicro)
                            .foregroundStyle(.dsTextTertiary)
                            .frame(width: DS.Size.controlXS)
                    }
                    .padding(.trailing, DS.Space.sm)
                    .frame(minHeight: DS.Size.minimumHitTarget)
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Archived")
                .accessibilityValue(isExpanded ? "Expanded" : "Collapsed")
                .padding(.top, DS.Space.md)

                if isExpanded {
                    ForEach(projects) { project in
                        ArchivedProjectRow(project: project)
                    }
                    ForEach(tasks) { summary in
                        ArchivedTaskRow(summary: summary) { select(summary.id) }
                    }
                }
            }
        }
    }
}

/// An archived project: its avatar and name, with Unarchive at hand and Delete in its menus.
private struct ArchivedProjectRow: View {
    @Environment(AppModel.self) private var model
    @Environment(\.projectIconStore) private var injectedIconStore
    let project: Project

    @State private var isConfirmingDelete = false

    var body: some View {
        HStack(spacing: DS.Space.md) {
            ProjectAvatar(name: project.name, icon: (injectedIconStore ?? .shared).icon(for: project))
            Text(project.name)
                .font(.dsCalloutBook)
                .foregroundStyle(.dsTextSecondary)
                .lineLimit(1)
            Spacer(minLength: 0)
            IconButton("Unarchive \(project.name)", systemImage: "arrow.uturn.backward", action: unarchive)
                .dsHitTarget(DS.Size.controlXS)
        }
        .padding(.leading, DS.Space.sm)
        .padding(.trailing, DS.Space.sm)
        .frame(minHeight: DS.Size.rowMinHeight)
        .contentShape(.rect)
        .help(project.path)
        .contextMenu {
            Button("Unarchive", action: unarchive)
            Button("Delete Project…", role: .destructive) { isConfirmingDelete = true }
        }
        .sidebarSwipeActions(trailing: [
            SidebarSwipeAction("Unarchive", systemImage: "arrow.uturn.backward", tint: .dsInfo, action: unarchive),
            SidebarSwipeAction("Delete", systemImage: "trash", tint: .dsDanger) { isConfirmingDelete = true },
        ])
        .projectDeletionConfirmation(project, isPresented: $isConfirmingDelete)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(project.name), archived project")
        .accessibilityActions {
            Button("Unarchive", action: unarchive)
            Button("Delete") { isConfirmingDelete = true }
        }
    }

    private func unarchive() {
        model.unarchiveProject(project.id)
    }
}

/// An archived task: opens to read on click, with Unarchive at its trailing edge and Delete in its
/// menus.
private struct ArchivedTaskRow: View {
    @Environment(AppModel.self) private var model
    @Environment(\.undoManager) private var undoManager
    let summary: SessionSummary
    let select: () -> Void

    @State private var isConfirmingDelete = false

    var body: some View {
        let title = model.title(for: summary)
        TaskRow(
            title: title,
            status: .idle,
            isSelected: model.selection == summary.id,
            date: summary.info.updatedDate,
            indent: .flat,
            leading: AgentIcon(agent: summary.agent),
            accessory: IconButton("Unarchive “\(title)”", systemImage: "arrow.uturn.backward", action: unarchive),
            action: select
        )
        .help("\(summary.agent.displayName) · \(title) · archived")
        .contextMenu {
            Button("Unarchive", action: unarchive)
            Button("Delete…", role: .destructive) { isConfirmingDelete = true }
        }
        .sidebarSwipeActions(trailing: [
            SidebarSwipeAction("Unarchive", systemImage: "arrow.uturn.backward", tint: .dsInfo, action: unarchive),
            SidebarSwipeAction("Delete", systemImage: "trash", tint: .dsDanger) { isConfirmingDelete = true },
        ])
        .accessibilityActions {
            Button("Unarchive", action: unarchive)
            Button("Delete") { isConfirmingDelete = true }
        }
        .confirmationDialog("Delete “\(title)”?", isPresented: $isConfirmingDelete) {
            Button("Delete Task", role: .destructive) {
                model.deleteSession(summary.id, undoManager: undoManager)
            }
        } message: {
            Text(
                "Its history goes from Native and, if \(summary.agent.displayName) supports it, from \(summary.agent.displayName) too. You can undo for a few seconds."
            )
        }
    }

    private func unarchive() {
        Task { await model.unarchiveSession(summary.id) }
    }
}
