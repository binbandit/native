import SwiftUI

/// A year of the user's work with agents as a graph, with the quiet game around it: the current and
/// longest streak, the busiest day and the year's total. Picking a day lists its tasks.
struct UsageActivityCard: View {
    let activity: ActivityLog
    let onOpen: (ActivityDay.Task) -> Void

    @State private var metric = ActivityMetric.prompts
    @State private var filter = ActivityFilter.all
    @State private var selection: Date?
    @State private var hovered: Date?
    @Environment(\.calendar) private var calendar
    @Environment(SettingsPresentation.self) private var settings

    var body: some View {
        let today = Date.now
        // The graph's year; the log keeps a few weeks more.
        let yearAgo = calendar.date(byAdding: .year, value: -1, to: calendar.startOfDay(for: today)) ?? today
        let values = activity.values(of: metric, for: filter).filter { $0.key > yearAgo }
        Card {
            VStack(alignment: .leading, spacing: DS.Space.lg) {
                header
                stats(ActivityStats(values: values.mapValues(\.value), today: today, calendar: calendar))
                ActivityHeatmap(
                    values: values.mapValues(\.value), estimated: Set(values.filter(\.value.isEstimate).keys), endingOn: today,
                    selection: $selection, hovered: $hovered
                ) { day in
                    describe(day, values[day])
                }
                readout(values)
                if let selection {
                    dayTasks(on: selection)
                }
            }
        }
    }

    private var header: some View {
        HStack(spacing: DS.Space.md) {
            Text("Activity")
                .font(.dsHeadline)
                .foregroundStyle(.dsTextPrimary)
            Spacer(minLength: DS.Space.md)
            SettingsSelect(
                label: "Show", selection: $filter,
                options: [.init(value: .all, title: "Everything")]
                    + activity.agents.map { .init(value: .agent($0.id), title: $0.name) }
                    + activity.projects.map { .init(value: .project($0.id), title: $0.name) })
            SettingsSelect(
                label: "Count", selection: $metric, options: ActivityMetric.allCases.map { .init(value: $0, title: $0.title) },
                width: UsageMetrics.metricSelectWidth)
        }
    }

    private func stats(_ stats: ActivityStats) -> some View {
        HStack(alignment: .top, spacing: DS.Space.xxl) {
            stat("Current streak", days(stats.currentStreak))
            stat("Longest streak", days(stats.longestStreak))
            stat(
                "Busiest day",
                stats.busiest.map { "\($0.day.formatted(.dateTime.month(.abbreviated).day())) · \(metric.describe($0.value))" } ?? "–")
            stat("Past year", metric.describe(stats.total))
        }
    }

    private func stat(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: DS.Space.xxs) {
            Text(title)
                .font(.dsCaption)
                .foregroundStyle(.dsTextTertiary)
            Text(value)
                .font(.dsBodyMedium)
                .foregroundStyle(.dsTextPrimary)
        }
        .accessibilityElement(children: .combine)
    }

    /// The hovered or picked day in numbers, so the graph never relies on color alone.
    private func readout(_ values: [Date: (value: Double, isEstimate: Bool)]) -> some View {
        let day = hovered ?? selection
        let text: String =
            if let day {
                describe(day, values[day]) + (values[day]?.isEstimate == true ? ", estimated from the agents’ session lists" : "")
            } else if values.isEmpty {
                filter == .all
                    ? "Each day you work with agents fills in a square. Days before Native counted are estimated from the agents’ session lists."
                    : "Nothing here in the past year. Show Everything to see all of your work."
            } else {
                "Hover over or tap a day to see it."
            }
        return Text(text)
            .font(.dsCaption)
            .foregroundStyle(day == nil ? .dsTextTertiary : .dsTextSecondary)
            .monospacedDigit()
            .fixedSize(horizontal: false, vertical: true)
    }

    @ViewBuilder
    private func dayTasks(on day: Date) -> some View {
        let tasks = activity.tasks(on: day, for: filter)
        VStack(alignment: .leading, spacing: 0) {
            ContributorSectionHeader(
                title: day.formatted(.dateTime.weekday(.wide).month(.wide).day()),
                tokens: tasks.count == 1 ? "1 task" : "\(tasks.count) tasks")
            if tasks.isEmpty {
                Text("No tasks that day.")
                    .font(.dsBody)
                    .foregroundStyle(.dsTextSecondary)
            }
            ForEach(tasks) { task in
                Button {
                    onOpen(task)
                    settings.close()
                } label: {
                    ContributorRow(
                        title: task.title ?? "Untitled task", detail: "\(task.agentName) · \(URL(filePath: task.project).lastPathComponent)",
                        tokens: "Open")
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .help("Open this task")
            }
        }
    }

    /// "12 prompts on Tuesday, March 4"
    private func describe(_ day: Date, _ entry: (value: Double, isEstimate: Bool)?) -> String {
        let date = day.formatted(.dateTime.weekday(.wide).month(.wide).day())
        guard let entry else { return "No \(metric.title.lowercased()) on \(date)" }
        return "\(metric.describe(entry.value, isEstimate: entry.isEstimate)) on \(date)"
    }

    private func days(_ count: Int) -> String {
        count == 1 ? "1 day" : "\(count) days"
    }
}
