import ACP
import SwiftUI

/// What the user archived, at the foot of the project list, collapsed until opened: archived
/// projects, then archived tasks, each with Unarchive and Delete. Archived tasks can still be
/// opened to read. Hidden when nothing is archived.
struct ArchivedSection: View {
    @Environment(AppModel.self) private var model
    @Environment(\.sidebarAllInView) private var isAllInView
    let select: (SessionKey) -> Void

    @AppStorage("sidebar.showsArchived") private var isExpanded = false

    var body: some View {
        let projects = model.projects.archived
        let groups = model.archivedTaskGroups
        let tasks = groups.flatMap(\.tasks)
        if !projects.isEmpty || !tasks.isEmpty {
            VStack(alignment: .leading, spacing: isAllInView ? 0 : DS.Space.xs) {
                if isAllInView {
                    // A fold, like "2 earlier": it hides rows rather than naming a group.
                    SidebarFoldRow("Archived", count: projects.count + tasks.count, isExpanded: $isExpanded)
                        .accessibilityLabel("Archived")
                        .padding(.top, DS.Space.md)
                } else {
                    header
                }

                if isExpanded {
                    ForEach(groups) { group in
                        VStack(alignment: .leading, spacing: isAllInView ? 0 : DS.Space.xxs) {
                            if group.isArchivedProject {
                                ArchivedProjectRow(project: group.project)
                            } else if isAllInView {
                                SidebarSectionLabel(group.project.name).padding(.bottom, DS.Space.xxs)
                            } else {
                                SectionHeader(group.project.name)
                                    .accessibilityAddTraits(.isHeader)
                            }
                            ForEach(group.tasks) { summary in
                                ArchivedTaskRow(summary: summary) { select(summary.id) }
                            }
                        }
                        .padding(.top, isAllInView ? DS.Sidebar.headerTop : 0)
                    }
                }
            }
        }
    }

    private var header: some View {
        let count = model.projects.archived.count + model.archivedTaskGroups.flatMap(\.tasks).count
        return Button {
            withAnimation(.dsDisclosure) { isExpanded.toggle() }
        } label: {
            SectionHeader("Archived") {
                Text("\(count)")
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
    }
}

/// An archived project: its avatar and name, with Unarchive at hand and Delete in its menus.
private struct ArchivedProjectRow: View {
    @Environment(AppModel.self) private var model
    @Environment(\.sidebarAllInView) private var isAllInView
    @Environment(\.projectIconStore) private var injectedIconStore
    let project: Project

    @State private var isConfirmingDelete = false

    var body: some View {
        content
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

    @ViewBuilder private var content: some View {
        if isAllInView {
            // A subhead like every other project's, so the archived projects don't read as siblings of
            // "Archived".
            SidebarSectionLabel(project.name) {
                IconButton("Unarchive \(project.name)", systemImage: "arrow.uturn.backward", action: unarchive)
                    .dsHitTarget(DS.Size.controlXS)
            }
            .padding(.bottom, DS.Space.xxs)
        } else {
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
        }
    }

    private func unarchive() {
        model.unarchiveProject(project.id)
    }
}

/// An archived task: opens to read on click, with Unarchive at its trailing edge and Delete in its
/// menus.
private struct ArchivedTaskRow: View {
    @AppStorage("sidebar.showAgentIcons") private var showAgentIcons = true
    @Environment(\.sidebarAllInView) private var isAllInView
    @Environment(AppModel.self) private var model
    @Environment(\.sidebarTaskInsights) private var insights
    @Environment(\.undoManager) private var undoManager
    let summary: SessionSummary
    let select: () -> Void

    var body: some View {
        let title = model.title(for: summary)
        Group {
            if isAllInView {
                AllInViewTaskRow(
                    title: title, status: .idle, isSelected: model.selection == summary.id,
                    outcome: insights.pullRequestBadge(summary), action: select
                )
                .task(id: [summary.info.cwd, insights.branch(summary) ?? ""]) {
                    await insights.prepare([summary])
                }
            } else {
                TaskRow(
                    title: title,
                    status: .idle,
                    isSelected: model.selection == summary.id,
                    date: model.lastActivity(for: summary),
                    indent: .grouped,
                    leading: AgentIcon(agent: summary.agent).opacity(showAgentIcons ? 1 : 0),
                    accessory: IconButton(
                        "Unarchive “\(title)”", systemImage: "arrow.uturn.backward", action: unarchive),
                    action: select
                )
            }
        }
        .help("\(summary.agent.displayName) · \(title) · archived")
        .contextMenu {
            Button("Unarchive", action: unarchive)
            if isAllInView, let pullRequest = insights.pullRequestMenu(summary) {
                Menu(pullRequest.title) {
                    ForEach(pullRequest.items) { item in Button(item.title, action: item.perform) }
                }
            }
            Button("Delete", role: .destructive, action: delete)
        }
        .sidebarSwipeActions(trailing: [
            SidebarSwipeAction("Unarchive", systemImage: "arrow.uturn.backward", tint: .dsInfo, action: unarchive),
            SidebarSwipeAction("Delete", systemImage: "trash", tint: .dsDanger, action: delete),
        ])
        .accessibilityLabel(
            [DSInlineCode.plain(title), isAllInView ? insights.pullRequestMenu(summary)?.spokenSummary : nil]
                .compactMap(\.self).joined(separator: ", ")
        )
        .accessibilityActions {
            Button("Unarchive", action: unarchive)
            Button("Delete", action: delete)
            if isAllInView, let pullRequest = insights.pullRequestMenu(summary) {
                ForEach(pullRequest.items) { item in Button(item.spokenTitle, action: item.perform) }
            }
        }
    }

    private func delete() {
        model.deleteSession(summary.id, undoManager: undoManager)
    }

    private func unarchive() {
        Task { await model.unarchiveSession(summary.id) }
    }
}

#if DEBUG
#Preview("Archived section") {
    let app = SidebarPreviewFixtures.archivedApp()
    let defaults = SidebarPreviewFixtures.defaults(showsArchived: true)
    DSPreviewPair {
        ArchivedSection(select: { _ in })
            .defaultAppStorage(defaults)
            .frame(width: DS.Size.sidebarWidth)
    }
    .sidebarPreviewEnvironment(app)
}
#Preview("All in view - Archived by project") {
    let app = SidebarPreviewFixtures.archivedApp()
    let defaults = SidebarPreviewFixtures.defaults(showAgentIcons: false, showsArchived: true)
    DSPreviewPair {
        ArchivedSection(select: { _ in })
            .environment(\.sidebarAllInView, true)
            .defaultAppStorage(defaults)
            .frame(width: DS.Size.sidebarWidth)
    }
    .sidebarPreviewEnvironment(app)
}
#endif
