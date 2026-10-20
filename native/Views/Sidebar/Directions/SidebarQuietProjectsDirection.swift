#if DEBUG
import SwiftUI

/// Direction B: today's projects tree, calmer. A project is its folder name in mono, with no avatar,
/// chevron or buttons until hovered. Rows carry no agent icons and no glyph at rest: a mark appears
/// only where something is happening or waits on the user, so the eye goes straight to it. Each
/// project shows its live tasks plus its latest few; the rest fold into "n more".
struct SidebarQuietProjectsDirection: View {
    @Environment(AppModel.self) private var model
    let destinations: SidebarDesignDestinations

    @State private var showsArchived = false

    var body: some View {
        let archived = model.sidebarDesignArchived()
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: DS.Space.xxs) {
                NewSessionItem()
                TranscriptSearchNavItem()
                SidebarDesignPullRequestsItem(destinations: destinations)
                if let workflows = destinations.workflows {
                    WorkflowsNavItem(isSelected: workflows.isShown, action: workflows.show)
                }
            }
            .padding(DS.Space.sm)

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(model.projects.all, id: \.id) { project in
                        QuietProjectGroup(project: project)
                    }
                    if !archived.isEmpty {
                        TriageDisclosureRow(title: "Archived \(archived.count)", isExpanded: showsArchived) {
                            withAnimation(.dsDisclosure) { showsArchived.toggle() }
                        }
                        .padding(.top, DS.Space.xl)
                        if showsArchived {
                            ForEach(archived) { task in
                                SidebarDesignRow(task: task, verticalPadding: DS.Space.sm) {
                                    Color.clear
                                } trailing: {
                                    Text(task.project.name)
                                        .font(.dsMonoCaption)
                                        .foregroundStyle(.dsTextTertiary)
                                }
                                .opacity(0.7)
                            }
                        }
                    }
                }
                .padding(.horizontal, DS.Space.sm)
                .padding(.bottom, DS.Space.md)
            }
            .scrollIndicators(.automatic)

            SidebarFooter()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
}

/// One project: its folder name, then its tasks. Live ones always show; quiet ones up to a few.
private struct QuietProjectGroup: View {
    @Environment(AppModel.self) private var model
    let project: Project

    @State private var isHovered = false
    @State private var showsAll = false

    /// How many tasks at rest a project shows before folding the rest.
    private static let restingLimit = 3

    var body: some View {
        let tasks = model.sidebarDesignTasks(in: project.id)
        let live = tasks.filter { $0.isYourMove || $0.status.isActive || $0.isUnread }
        let resting = tasks.filter { !($0.isYourMove || $0.status.isActive || $0.isUnread) }
        let shownResting = showsAll ? resting : Array(resting.prefix(Self.restingLimit))
        let shown = Set(live.map(\.id) + shownResting.map(\.id))

        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: DS.Space.sm) {
                Text(project.name)
                    .font(.dsMono)
                    .foregroundStyle(.dsTextTertiary)
                    .lineLimit(1)
                Spacer(minLength: 0)
                IconButton("New Session in \(project.name)", systemImage: "plus") {
                    Task { await model.newSession(in: project.id) }
                }
                .opacity(isHovered || DS.isTouchPlatform ? 1 : 0)
            }
            .padding(.leading, DS.Space.sm)
            .padding(.top, DS.Space.xl)
            .padding(.bottom, DS.Space.xxs)
            .contentShape(.rect)
            .trackHover($isHovered)
            .accessibilityElement(children: .contain)
            .accessibilityLabel(project.name)

            if tasks.isEmpty {
                SidebarDesignStartRow(title: "Start the first task") {
                    Task { await model.newSession(in: project.id) }
                }
            }
            // The project's own order, with the folded ones left out.
            ForEach(tasks.filter { shown.contains($0.id) }) { task in
                SidebarDesignRow(task: task, verticalPadding: DS.Space.sm) {
                    SidebarDesignMark(task: task)
                } trailing: {
                    if let device = task.device {
                        SidebarDesignDevice(name: device)
                    }
                    if let nextStep = task.nextStep {
                        Text(nextStep)
                            .font(.dsCaptionMedium)
                            .foregroundStyle(task.status == .failed ? .dsDanger : .dsAttention)
                    } else if let date = task.date {
                        CompactAgeText(date: date)
                    }
                }
            }
            if resting.count > Self.restingLimit {
                TriageDisclosureRow(
                    title: showsAll ? "Show less" : "\(resting.count - Self.restingLimit) more",
                    isExpanded: showsAll
                ) { withAnimation(.dsDisclosure) { showsAll.toggle() } }
            }
        }
    }
}
#endif
