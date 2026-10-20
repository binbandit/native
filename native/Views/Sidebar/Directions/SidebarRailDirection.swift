#if DEBUG
import SwiftUI

/// Direction C: a thin rail that gives the window back to the work. It holds New Session, Search,
/// each project as a tile with a mark for every task that's live in it, then the pages. Opening it
/// (a tile, or the rail's toggle) slides out a keyboard navigator: a filter field, every task with
/// its ⌘1 – ⌘9 key shown, and ↑ ↓ Return to move and open.
struct SidebarRailDirection: View {
    let destinations: SidebarDesignDestinations

    @State private var focusedProject: Project.ID?
    private let rail = SidebarDesignRailState.shared

    var body: some View {
        HStack(spacing: 0) {
            SidebarRailColumn(destinations: destinations, focusedProject: $focusedProject)
                .frame(width: SidebarDesignRailState.railWidth)
            if rail.isExpanded {
                SeparatorLine(axis: .vertical)
                SidebarRailNavigator(focusedProject: $focusedProject)
                    .frame(width: SidebarDesignRailState.navigatorWidth - 1)
                    .transition(.opacity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

/// The rail itself: actions at the top, projects with their live marks, the pages at the bottom.
private struct SidebarRailColumn: View {
    @Environment(AppModel.self) private var model
    @Environment(GitHubModel.self) private var gitHub
    @Environment(SettingsPresentation.self) private var settings
    let destinations: SidebarDesignDestinations
    @Binding var focusedProject: Project.ID?
    private let rail = SidebarDesignRailState.shared

    var body: some View {
        VStack(spacing: DS.Space.sm) {
            SidebarRailButton("New Session (⌘N)", systemImage: "plus", isOutlined: true) {
                Task { await model.newSession() }
            }
            SidebarRailButton("Search (⇧⌘F)", systemImage: "magnifyingglass") {
                TranscriptSearch.open()
            }
            SeparatorLine()
                .frame(width: DS.Size.controlSM)
                .padding(.vertical, DS.Space.xs)
            ScrollView {
                VStack(spacing: DS.Space.lg) {
                    ForEach(model.projects.all, id: \.id) { project in
                        let tasks = model.sidebarDesignTasks(in: project.id)
                        SidebarRailProjectTile(
                            project: project,
                            tasks: tasks,
                            isFocused: rail.isExpanded && focusedProject == project.id,
                            holdsSelection: tasks.contains { $0.id == model.selection }
                        ) {
                            withAnimation(.dsPanel) {
                                if rail.isExpanded, focusedProject == project.id {
                                    focusedProject = nil
                                } else {
                                    focusedProject = project.id
                                    rail.isExpanded = true
                                }
                            }
                        }
                    }
                }
                .padding(.vertical, DS.Space.xs)
            }
            .scrollIndicators(.never)
            Spacer(minLength: 0)
            SidebarRailButton(
                "Pull Requests (⇧⌘P)", systemImage: "arrow.triangle.pull",
                isSelected: destinations.isShowingPullRequests, badge: SidebarDesignFixture.reviewRequests(gitHub),
                action: destinations.showPullRequests)
            if let workflows = destinations.workflows {
                SidebarRailButton(
                    "Workflows", systemImage: "point.3.connected.trianglepath.dotted", isSelected: workflows.isShown,
                    action: workflows.show)
            }
            SidebarRailButton(
                rail.isExpanded ? "Close the Navigator" : "Open the Navigator", systemImage: "sidebar.left",
                isSelected: rail.isExpanded
            ) {
                withAnimation(.dsPanel) { rail.isExpanded.toggle() }
            }
            SidebarRailButton("Settings (⌘,)", systemImage: "gearshape") {
                settings.open()
            }
        }
        .padding(.top, DS.Space.sm)
        .padding(.bottom, DS.Space.lg)
        .frame(maxHeight: .infinity, alignment: .top)
    }
}

/// A 36pt square rail control: a glyph, a hover wash, an optional outline and count.
private struct SidebarRailButton: View {
    let title: String
    let systemImage: String
    var isOutlined = false
    var isSelected = false
    var badge = 0
    let action: () -> Void

    @State private var isHovered = false

    init(
        _ title: String, systemImage: String, isOutlined: Bool = false, isSelected: Bool = false, badge: Int = 0,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.systemImage = systemImage
        self.isOutlined = isOutlined
        self.isSelected = isSelected
        self.badge = badge
        self.action = action
    }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous)
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 14, weight: .regular))
                .foregroundStyle(isHovered || isSelected ? .dsTextPrimary : .dsTextSecondary)
                .frame(width: SidebarRailMetrics.tile, height: SidebarRailMetrics.tile)
                .background(isSelected ? .dsSelected : isHovered ? .dsHover : .clear, in: shape)
                .overlay {
                    if isOutlined {
                        shape.strokeBorder(isHovered ? .dsBorderHover : .dsBorder, lineWidth: 1)
                    }
                }
                .overlay(alignment: .topTrailing) {
                    if badge > 0 {
                        SidebarRailCount(count: badge, tone: .neutral)
                            .offset(x: DS.Space.xs, y: -DS.Space.xxs)
                    }
                }
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .trackHover($isHovered)
        .help(title)
        .accessibilityLabel(title)
    }
}

/// A project on the rail: its icon on a tile, its name, and one mark per live task (working,
/// waiting on the user, failed, or finished and unread). Waiting tasks also count on the tile.
private struct SidebarRailProjectTile: View {
    let project: Project
    let tasks: [SidebarDesignTask]
    let isFocused: Bool
    /// The open task is one of the project's: the tile is where you are.
    let holdsSelection: Bool
    let action: () -> Void

    @State private var isHovered = false
    private let iconStore = ProjectIconStore.shared

    /// More marks than this read as noise; the navigator has the rest.
    private static let markLimit = 4

    var body: some View {
        let live = tasks.filter { $0.isYourMove || $0.status.isActive || $0.isUnread }
            .sorted { $0.isYourMove && !$1.isYourMove }
        let waiting = tasks.count { $0.status.needsAttention }
        let shape = RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous)
        Button(action: action) {
            VStack(spacing: DS.Space.xs) {
                ProjectAvatar(name: project.name, icon: iconStore.icon(for: project, size: 20), size: 20)
                    .frame(width: SidebarRailMetrics.tile, height: SidebarRailMetrics.tile)
                    .background(isFocused || holdsSelection ? .dsSelected : isHovered ? .dsHover : .clear, in: shape)
                    .overlay {
                        shape.strokeBorder(isFocused || holdsSelection ? .dsBorderStrong : .dsBorder, lineWidth: 1)
                    }
                    .overlay(alignment: .topTrailing) {
                        if waiting > 0 {
                            SidebarRailCount(count: waiting, tone: .attention)
                                .offset(x: DS.Space.xs, y: -DS.Space.xxs)
                        }
                    }
                Text(project.name)
                    .font(.dsMicro)
                    .foregroundStyle(isFocused || isHovered ? .dsTextSecondary : .dsTextTertiary)
                    .lineLimit(1)
                    .frame(maxWidth: SidebarDesignRailState.railWidth - DS.Space.lg)
                HStack(spacing: DS.Space.xs) {
                    ForEach(live.prefix(Self.markLimit)) { task in
                        SidebarRailMark(task: task)
                    }
                    if live.count > Self.markLimit {
                        Text("+\(live.count - Self.markLimit)")
                            .font(.dsMonoMicro)
                            .foregroundStyle(.dsTextTertiary)
                    }
                }
                .frame(height: 6)
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .trackHover($isHovered)
        .help(helpText(live: live.count, waiting: waiting))
        .accessibilityLabel(project.name)
        .accessibilityValue(helpText(live: live.count, waiting: waiting))
        .task(id: project.id) { await iconStore.resolve(project) }
    }

    private func helpText(live: Int, waiting: Int) -> String {
        let working = tasks.count { $0.status.isActive }
        let parts = [
            waiting > 0 ? "\(waiting) waiting on you" : nil, working > 0 ? "\(working) working" : nil,
        ].compactMap(\.self)
        return "\(project.name)\(parts.isEmpty ? "" : ": " + parts.joined(separator: ", "))"
    }
}

/// A small count on a rail tile's corner.
private struct SidebarRailCount: View {
    enum Tone { case neutral, attention }
    let count: Int
    let tone: Tone

    var body: some View {
        Text("\(count)")
            .font(.dsMonoMicro)
            .foregroundStyle(tone == .attention ? .dsTextInverse : .dsTextSecondary)
            .padding(.horizontal, DS.Space.xs)
            .frame(minWidth: 14, minHeight: 14)
            .background(tone == .attention ? .dsAttention : .dsSelected, in: .capsule)
    }
}

/// One live task under a project tile: a ring while the agent works, a dot in the status's color
/// when it's the user's move or a result is waiting to be read.
private struct SidebarRailMark: View {
    let task: SidebarDesignTask

    var body: some View {
        if task.status.isActive, !task.isYourMove {
            Circle()
                .strokeBorder(.dsTextSecondary, lineWidth: 1)
                .frame(width: 6, height: 6)
        } else {
            Circle()
                .fill(color)
                .frame(width: 6, height: 6)
        }
    }

    private var color: Color {
        if task.status.needsAttention { return .dsAttention }
        if task.status == .failed { return .dsDanger }
        return .dsTextPrimary
    }
}

enum SidebarRailMetrics {
    static let tile: CGFloat = 36
}
#endif
