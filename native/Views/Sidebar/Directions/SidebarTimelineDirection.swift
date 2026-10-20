#if DEBUG
import SwiftUI

/// Direction D: what happened, in order. Every task is one entry on a thread, at the time of its
/// latest event, with that event under its title ("Finished, 1 file changed", "Codex exited
/// mid-turn"). What waits on the user sits above the thread; what's running is "Now". Archived
/// tasks stay in the history, dimmed. It answers "what did my agents do while I was away?".
struct SidebarTimelineDirection: View {
    @Environment(AppModel.self) private var model
    let destinations: SidebarDesignDestinations

    var body: some View {
        let tasks = model.sidebarDesignTasks()
        let waiting = tasks.filter(\.isYourMove)
        let history = (tasks.filter { !$0.isYourMove } + model.sidebarDesignArchived())
            .sorted { ($0.date ?? .distantPast) > ($1.date ?? .distantPast) }
        let groups = TimelineBucket.group(history, now: .now)

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
            SeparatorLine()
                .padding(.horizontal, DS.Space.lg)

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    if !waiting.isEmpty {
                        TimelineHeader(title: "Waiting on you", isAttention: true)
                        ForEach(waiting) { task in
                            TimelineEntry(task: task, time: .age, isLast: task.id == waiting.last?.id)
                        }
                    }
                    ForEach(groups) { group in
                        TimelineHeader(title: group.bucket.title, isAttention: false)
                        ForEach(group.tasks) { task in
                            TimelineEntry(
                                task: task, time: group.bucket.timeStyle, isLast: task.id == group.tasks.last?.id)
                        }
                    }
                    if tasks.count < 3 {
                        TimelineEmptyNote()
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

/// Where an entry falls in time, and how its time reads there.
private enum TimelineBucket: Int, CaseIterable {
    case now, today, yesterday, thisWeek, earlier

    enum TimeStyle { case age, clock, weekday, date }

    var title: String {
        switch self {
        case .now: "Now"
        case .today: "Today"
        case .yesterday: "Yesterday"
        case .thisWeek: "This week"
        case .earlier: "Earlier"
        }
    }

    var timeStyle: TimeStyle {
        switch self {
        case .now: .age
        case .today, .yesterday: .clock
        case .thisWeek: .weekday
        case .earlier: .date
        }
    }

    struct Span: Identifiable {
        let bucket: TimelineBucket
        let tasks: [SidebarDesignTask]
        var id: TimelineBucket { bucket }
    }

    static func group(_ tasks: [SidebarDesignTask], now: Date) -> [Span] {
        let calendar = Calendar.current
        let grouped = Dictionary(grouping: tasks) { task -> Self in
            if task.status.isActive { return .now }
            guard let date = task.date else { return .earlier }
            if calendar.isDate(date, inSameDayAs: now) { return .today }
            if calendar.isDateInYesterday(date) { return .yesterday }
            if let week = calendar.date(byAdding: .day, value: -7, to: now), date > week { return .thisWeek }
            return .earlier
        }
        return allCases.compactMap { bucket in grouped[bucket].map { Span(bucket: bucket, tasks: $0) } }
    }
}

/// A group's name, with a hairline running to the edge.
private struct TimelineHeader: View {
    let title: String
    let isAttention: Bool

    var body: some View {
        HStack(spacing: DS.Space.md) {
            Text(title)
                .font(.dsCaptionMedium)
                .foregroundStyle(isAttention ? .dsAttention : .dsTextTertiary)
                .fixedSize()
            SeparatorLine()
        }
        .padding(.leading, DS.Space.sm)
        .padding(.trailing, DS.Space.xs)
        .padding(.top, DS.Space.lg)
        .padding(.bottom, DS.Space.xs)
        .accessibilityAddTraits(.isHeader)
    }
}

/// One task on the thread: a node in the status's color on a line that runs down the group, the
/// title, then its latest event with the project, agent and machine.
private struct TimelineEntry: View {
    @Environment(AppModel.self) private var model
    @Environment(\.undoManager) private var undoManager
    let task: SidebarDesignTask
    let time: TimelineBucket.TimeStyle
    let isLast: Bool

    @State private var isHovered = false

    private var isSelected: Bool { model.selection == task.id }

    var body: some View {
        Button {
            model.selectFromSidebarDesign(task.id)
        } label: {
            HStack(alignment: .top, spacing: DS.Space.md) {
                TimelineNode(task: task)
                VStack(alignment: .leading, spacing: DS.Space.xxs) {
                    HStack(spacing: DS.Space.sm) {
                        DSInlineCodeText(task.title)
                            .font(task.isUnread ? .dsCalloutSemibold : .dsCalloutBook)
                            .foregroundStyle(task.isUnread || isSelected ? .dsTextPrimary : .dsTextSecondary)
                            .lineLimit(1)
                        Spacer(minLength: 0)
                        TimelineTime(date: task.date, style: time)
                    }
                    .frame(height: 20)
                    DSInlineCodeText(eventLine, codeFont: .dsMonoCaption)
                        .font(.dsCaption)
                        .foregroundStyle(SidebarDesignTone(task).color)
                        .lineLimit(1)
                }
            }
            .padding(.vertical, DS.Space.sm)
            .padding(.leading, DS.Space.sm)
            .padding(.trailing, DS.Space.sm)
            // The thread: from under this entry's node into the next entry, to just above its node.
            .background(alignment: .topLeading) {
                if !isLast {
                    SeparatorLine(axis: .vertical)
                        .padding(.top, DS.Space.sm + DS.Space.xxs + DS.Size.rowLeading + DS.Space.xxs)
                        .padding(.bottom, -(DS.Space.sm + DS.Space.xxs))
                        .padding(.leading, DS.Space.sm + DS.Size.rowLeading / 2 - 0.5)
                }
            }
            .contentShape(.rect)
        }
        .buttonStyle(SidebarRowButtonStyle())
        .background {
            RoundedRectangle(cornerRadius: DS.Radius.row, style: .continuous)
                .fill(isSelected ? .dsSelected : isHovered ? .dsHover : .clear)
        }
        .opacity(task.isArchived ? 0.55 : 1)
        .trackHover($isHovered)
        .help([task.title, task.event].joined(separator: "\n"))
        .accessibilityLabel(task.title)
        .accessibilityValue(eventLine)
        .contextMenu {
            Button(task.isUnread ? "Mark as Read" : "Mark as Unread") { model.setUnread(task.id, !task.isUnread) }
            Divider()
            if task.isArchived {
                Button("Unarchive") { Task { await model.unarchiveSession(task.id) } }
            } else {
                Button("Archive") { Task { await model.archiveSession(task.id, undoManager: undoManager) } }
            }
        }
    }

    /// "native · Finished, 1 file changed", or the ask itself while it waits: the event first when
    /// it's the user's move, the project first otherwise.
    private var eventLine: String {
        let place = [task.project.name, task.device.map { "on \($0)" }].compactMap(\.self).joined(separator: " ")
        let event = task.isArchived ? "Archived" : task.event
        return task.isYourMove ? "\(event) · \(place)" : "\(place) · \(event)"
    }
}

/// The node on the thread: the live loader, a ring for what waits or failed, a filled dot for a
/// result not yet seen, and a small hollow dot for the rest.
private struct TimelineNode: View {
    let task: SidebarDesignTask

    var body: some View {
        Group {
            if task.status.isActive || task.isYourMove {
                StatusIndicator(status: task.status, size: DS.Size.rowLeading)
            } else if task.isUnread {
                Circle().fill(.dsAccent).frame(width: 7, height: 7)
            } else {
                Circle().strokeBorder(.dsTextTertiary, lineWidth: 1.2).frame(width: 7, height: 7)
            }
        }
        .frame(width: DS.Size.rowLeading, height: DS.Size.rowLeading)
        .padding(.top, DS.Space.xxs)
    }
}

/// An entry's time: an age while live, the clock today and yesterday, the weekday this week, the
/// date before that.
private struct TimelineTime: View {
    let date: Date?
    let style: TimelineBucket.TimeStyle

    var body: some View {
        if let date {
            Group {
                switch style {
                case .age: CompactAgeText(date: date)
                case .clock: Text(date.formatted(date: .omitted, time: .shortened))
                case .weekday: Text(date.formatted(.dateTime.weekday(.abbreviated)))
                case .date: Text(date.formatted(.dateTime.month(.abbreviated).day()))
                }
            }
            .font(.dsCaption)
            .foregroundStyle(.dsTextTertiary)
            .monospacedDigit()
        }
    }
}

/// Under a short history: what this list is and how it fills.
private struct TimelineEmptyNote: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.sm) {
            Text("Everything your agents do lands here, newest first. Start a task and it shows up at the top.")
                .font(.dsBody)
                .foregroundStyle(.dsTextTertiary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, DS.Space.sm)
                .padding(.top, DS.Space.xl)
            ForEach(model.projects.all, id: \.id) { project in
                SidebarDesignStartRow(title: "Start a task in \(project.name)") {
                    Task { await model.newSession(in: project.id) }
                }
            }
        }
    }
}
#endif
