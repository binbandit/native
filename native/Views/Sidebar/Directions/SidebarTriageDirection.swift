#if DEBUG
import SwiftUI

/// Direction A: the sidebar sorted by whose move it is, across every project. "Your move" holds what
/// waits on the user (approvals, questions, failures, and pull requests to review), "Running" what
/// the agents are doing right now with the step they're on, then "Recent". Projects become a scope
/// and a tag on each row instead of the structure. A quiet day leaves only Recent.
struct SidebarTriageDirection: View {
    @Environment(AppModel.self) private var model
    @Environment(GitHubModel.self) private var gitHub
    let destinations: SidebarDesignDestinations

    @State private var scope: Project.ID?
    @State private var showsAllRecent = false
    @State private var showsArchived = false

    /// Recent stays short; the rest is a click (or Search) away.
    private static let recentLimit = 7

    var body: some View {
        let tasks = model.sidebarDesignTasks(in: scope)
        let yourMove = tasks.filter(\.isYourMove)
        let running = tasks.filter { $0.status.isActive && !$0.isYourMove }
        let recent = tasks.filter { !$0.isYourMove && !$0.status.isActive }
            .sorted { lhs, rhs in
                lhs.isUnread != rhs.isUnread ? lhs.isUnread : (lhs.date ?? .distantPast) > (rhs.date ?? .distantPast)
            }
        let archived = model.sidebarDesignArchived(in: scope)
        let reviews = scope == nil ? SidebarDesignFixture.reviewRequests(gitHub) : 0

        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: DS.Space.xxs) {
                NewSessionItem()
                TranscriptSearchNavItem()
                if let workflows = destinations.workflows {
                    WorkflowsNavItem(isSelected: workflows.isShown, action: workflows.show)
                }
            }
            .padding(DS.Space.sm)

            SeparatorLine()
                .padding(.horizontal, DS.Space.lg)

            ScrollView {
                LazyVStack(alignment: .leading, spacing: DS.Space.xxs) {
                    TriageScopeMenu(scope: $scope)

                    if yourMove.isEmpty, reviews == 0 {
                        Text(
                            running.isEmpty ? "Nothing needs you right now." : "Nothing needs you. Agents are working."
                        )
                        .font(.dsBody)
                        .foregroundStyle(.dsTextTertiary)
                        .padding(.horizontal, DS.Space.sm)
                        .padding(.vertical, DS.Space.md)
                    } else {
                        TriageSectionHeader(title: "Your move", count: yourMove.count + (reviews > 0 ? 1 : 0))
                        ForEach(yourMove) { task in
                            SidebarDesignRow(task: task, detail: task.detail, detailTone: SidebarDesignTone(task)) {
                                StatusIndicator(status: task.status)
                            } trailing: {
                                TriageProjectTag(task: task, showsProject: scope == nil)
                            }
                        }
                        if reviews > 0 {
                            TriageLinkRow(
                                title: "Review \(reviews) pull \(reviews == 1 ? "request" : "requests")",
                                systemImage: "arrow.triangle.pull",
                                isSelected: destinations.isShowingPullRequests,
                                action: destinations.showPullRequests)
                        }
                    }

                    if !running.isEmpty {
                        TriageSectionHeader(title: "Running", count: running.count)
                        ForEach(running) { task in
                            SidebarDesignRow(task: task, detail: task.detail) {
                                StatusIndicator(status: task.status)
                            } trailing: {
                                TriageProjectTag(task: task, showsProject: scope == nil)
                            }
                        }
                    }

                    if !recent.isEmpty {
                        TriageSectionHeader(title: "Recent", count: nil)
                        let shown = showsAllRecent ? recent : Array(recent.prefix(Self.recentLimit))
                        ForEach(shown) { task in
                            SidebarDesignRow(task: task) {
                                SidebarDesignMark(task: task)
                            } trailing: {
                                TriageProjectTag(task: task, showsProject: scope == nil)
                                if let date = task.date {
                                    CompactAgeText(date: date)
                                }
                            }
                        }
                        if recent.count > Self.recentLimit {
                            TriageDisclosureRow(
                                title: showsAllRecent ? "Show less" : "\(recent.count - Self.recentLimit) more",
                                isExpanded: showsAllRecent
                            ) { withAnimation(.dsDisclosure) { showsAllRecent.toggle() } }
                        }
                    }

                    // A nearly empty sidebar offers the one action that fills it, per project.
                    if tasks.count < 3 {
                        TriageSectionHeader(title: "Start a task", count: nil)
                        ForEach(model.projects.all.filter { scope == nil || $0.id == scope }) { project in
                            SidebarDesignStartRow(title: project.name) {
                                Task { await model.newSession(in: project.id) }
                            }
                        }
                    }

                    if !archived.isEmpty {
                        TriageDisclosureRow(title: "Archived \(archived.count)", isExpanded: showsArchived) {
                            withAnimation(.dsDisclosure) { showsArchived.toggle() }
                        }
                        .padding(.top, DS.Space.md)
                        if showsArchived {
                            ForEach(archived) { task in
                                SidebarDesignRow(task: task) {
                                    Color.clear
                                } trailing: {
                                    TriageProjectTag(task: task, showsProject: scope == nil)
                                }
                                .opacity(0.7)
                            }
                        }
                    }
                }
                .padding(.horizontal, DS.Space.sm)
                .padding(.vertical, DS.Space.md)
            }
            .scrollIndicators(.automatic)

            SidebarFooter()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
}

/// Which projects the triage covers: all of them, or one.
private struct TriageScopeMenu: View {
    @Environment(AppModel.self) private var model
    @Binding var scope: Project.ID?

    var body: some View {
        let name = scope.flatMap { model.projects.project($0)?.name } ?? "All projects"
        HStack(spacing: DS.Space.xs) {
            Menu {
                Button("All projects") { scope = nil }
                Divider()
                ForEach(model.projects.all) { project in
                    Button(project.name) { scope = project.id }
                }
                Divider()
                Button("Add Project…") { model.isAddingProject = true }
            } label: {
                HStack(spacing: DS.Space.xs) {
                    Text(name)
                        .font(.dsBodyMedium)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 8, weight: .semibold))
                }
                .foregroundStyle(.dsTextTertiary)
                .contentShape(.rect)
            }
            .menuStyle(.button)
            .buttonStyle(.plain)
            .menuIndicator(.hidden)
            .fixedSize()
            .help("Show every project's tasks, or one project's")
            Spacer(minLength: 0)
        }
        .padding(.horizontal, DS.Space.sm)
        .frame(minHeight: DS.Size.controlXS)
    }
}

/// A section's name and how many tasks are in it.
private struct TriageSectionHeader: View {
    let title: String
    let count: Int?

    var body: some View {
        HStack(spacing: DS.Space.sm) {
            Text(title)
                .font(.dsBodyMedium)
                .foregroundStyle(.dsTextSecondary)
            if let count {
                Text("\(count)")
                    .font(.dsMonoCaption)
                    .foregroundStyle(.dsTextTertiary)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, DS.Space.sm)
        .padding(.top, DS.Space.lg)
        .padding(.bottom, DS.Space.xxs)
        .accessibilityAddTraits(.isHeader)
    }
}

/// The project (and machine) a row belongs to, at its trailing edge.
private struct TriageProjectTag: View {
    let task: SidebarDesignTask
    let showsProject: Bool

    var body: some View {
        if let device = task.device {
            SidebarDesignDevice(name: device, showsName: false)
        }
        if showsProject {
            Text(task.project.name)
                .font(.dsCaption)
                .foregroundStyle(.dsTextTertiary)
                .lineLimit(1)
        }
    }
}

/// A row that opens a page rather than a task: pull requests waiting on the user's review.
private struct TriageLinkRow: View {
    let title: String
    let systemImage: String
    let isSelected: Bool
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: DS.Space.md) {
                Image(systemName: systemImage)
                    .font(.system(size: 11))
                    .foregroundStyle(.dsAttention)
                    .frame(width: DS.Size.rowLeading, height: DS.Size.rowLeading)
                Text(title)
                    .font(.dsCalloutBook)
                    .foregroundStyle(isSelected ? .dsTextPrimary : .dsTextSecondary)
                Spacer(minLength: 0)
                Text("GitHub")
                    .font(.dsCaption)
                    .foregroundStyle(.dsTextTertiary)
            }
            .padding(.vertical, DS.Space.md)
            .padding(.horizontal, DS.Space.sm)
            .contentShape(.rect)
        }
        .buttonStyle(SidebarRowButtonStyle())
        .background {
            RoundedRectangle(cornerRadius: DS.Radius.row, style: .continuous)
                .fill(isSelected ? .dsSelected : isHovered ? .dsHover : .clear)
        }
        .trackHover($isHovered)
    }
}

/// "3 more", "Archived 6": a quiet row that opens what it counts.
struct TriageDisclosureRow: View {
    let title: String
    let isExpanded: Bool
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: DS.Space.md) {
                Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                    .font(.system(size: 9, weight: .semibold))
                    .frame(width: DS.Size.rowLeading, height: DS.Size.rowLeading)
                Text(title)
                    .font(.dsBody)
                Spacer(minLength: 0)
            }
            .foregroundStyle(isHovered ? .dsTextSecondary : .dsTextTertiary)
            .padding(.vertical, DS.Space.sm)
            .padding(.horizontal, DS.Space.sm)
            .contentShape(.rect)
        }
        .buttonStyle(SidebarRowButtonStyle())
        .trackHover($isHovered)
    }
}
#endif
