import SwiftUI
import TaskList

/// The projects and their sessions as a tree: a "Projects" header with the window's filters and an
/// add button, the active filters as chips, each project as a collapsible group in the user's
/// order, then what's archived. Collapsed projects are remembered, and a project expands when one
/// of its sessions is selected. While filters narrow the list, projects with matches show expanded
/// and the rest collapse with a note saying so.
struct ProjectList<TaskAccessory: View>: View {
    @Environment(AppModel.self) private var model
    @Environment(\.sidebarQuietProjects) private var isQuiet
    let listing: SidebarListing
    let taskAccessory: (SessionSummary) -> TaskAccessory
    @Binding var filter: TaskFilter
    let selection: SidebarSelectionModel
    let select: (SessionKey) -> Void

    @AppStorage(CollapsedProjects.storageKey) private var collapsed = CollapsedProjects()
    @State private var drag = SidebarDragState()

    var body: some View {
        @Bindable var selection = selection
        let isNarrowing = filter.isNarrowing
        // Lazy, so only the projects on screen are built (each lazy about its own rows too).
        LazyVStack(alignment: .leading, spacing: DS.Space.xxs) {
            if !listing.pinned.isEmpty {
                PinnedSection(
                    sessions: listing.pinned, order: Self.positions(listing.allPinned), drag: drag,
                    taskAccessory: taskAccessory, select: select)
            }
            SectionHeader(isQuiet ? "" : "Projects") {
                SidebarFilterButton(filter: $filter, isSelecting: $selection.isSelecting)
                IconButton("Add Project", systemImage: "folder.badge.plus") {
                    model.isAddingProject = true
                }
            }
            // Lines the buttons up with the projects' "+" buttons.
            .padding(.trailing, DS.Space.sm)

            if filter.isActive {
                SidebarFilterChips(filter: $filter)
            }
            if model.projects.all.isEmpty {
                AddProjectPrompt()
            } else if isNarrowing, listing.isEmpty, model.startingTasks.isEmpty {
                NothingMatches { filter.clearFilters() }
            }
            ForEach(Array(listing.groups.enumerated()), id: \.element.project.id) { index, group in
                let project = group.project
                let hasNoMatches =
                    isNarrowing && group.visible.isEmpty && model.startingTasks(in: project.id).isEmpty
                ProjectSection(
                    project: project,
                    sessions: group.visible,
                    order: Self.positions(group.all),
                    position: (index, listing.groups.count),
                    isFiltered: isNarrowing,
                    allowsFolding: !filter.isActive,
                    hasNoMatches: hasNoMatches,
                    isExpanded: Binding(
                        get: { isNarrowing ? !hasNoMatches : !collapsed.contains(project.id) },
                        set: { collapsed.set(project.id, collapsed: !$0) }
                    ),
                    drag: drag,
                    taskAccessory: taskAccessory,
                    select: select
                )
            }
            // Archived tasks show in their projects while the filter includes them.
            if !isNarrowing, !filter.includesArchived {
                ArchivedSection(select: select)
            }
        }
        .onChange(of: model.selection) {
            guard let selection = model.selection,
                let project = model.catalog.lookup(selection)?.project ?? model.startingTask(selection)?.project,
                collapsed.contains(project)
            else { return }
            withAnimation(.dsDisclosure) {
                collapsed.set(project, collapsed: false)
            }
        }
    }

    private static func positions(_ sessions: [SessionSummary]) -> [SessionKey: Int] {
        Dictionary(sessions.enumerated().map { ($1.id, $0) }, uniquingKeysWith: { first, _ in first })
    }
}

/// The empty tree: a dashed button to add the first project.
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

/// The filters match no task anywhere: say so, and offer the way back.
private struct NothingMatches: View {
    let clear: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.sm) {
            Text("No tasks match these filters. Tasks show up here as soon as they do.")
                .font(.dsBody)
                .foregroundStyle(.dsTextTertiary)
                .fixedSize(horizontal: false, vertical: true)
            // Ghost, so nothing opaque sits on the translucent sidebar.
            Button("Clear Filters", action: clear)
                .buttonStyle(.ds(.ghost))
        }
        .padding(.horizontal, DS.Space.sm)
        .padding(.vertical, DS.Space.md)
    }
}

#if DEBUG
#Preview("Project list") {
    let app = AppModel.preview()
    DSPreviewPair {
        ProjectListPreview(app: app, filter: TaskFilter())
    }
    .sidebarPreviewEnvironment(app)
}

#Preview("Project list - Filtered") {
    let app = AppModel.preview()
    DSPreviewPair {
        ProjectListPreview(app: app, filter: TaskFilter(statuses: [.needsYou]))
    }
    .sidebarPreviewEnvironment(app)
}

#Preview("Project list - Nothing matches") {
    let app = AppModel.preview()
    DSPreviewPair {
        ProjectListPreview(app: app, filter: TaskFilter(statuses: [.failed], agents: ["claude-code"]))
    }
    .sidebarPreviewEnvironment(app)
}

#Preview("Project list - No projects") {
    let app = AppModel.preview(.empty)
    DSPreviewPair {
        ProjectListPreview(app: app, filter: TaskFilter())
    }
    .sidebarPreviewEnvironment(app)
}

/// The list as the sidebar builds it, with the filter in state so its chips and menu work.
private struct ProjectListPreview: View {
    let app: AppModel
    @State var filter: TaskFilter
    @State private var selection = SidebarSelectionModel()

    var body: some View {
        ProjectList(
            listing: SidebarListing(model: app, filter: filter, insights: SidebarTaskInsights()),
            taskAccessory: { SessionContextUsage(summary: $0) }, filter: $filter, selection: selection,
            select: { _ in }
        )
        .frame(width: DS.Size.sidebarWidth - DS.Space.lg, alignment: .top)
    }
}
#endif
