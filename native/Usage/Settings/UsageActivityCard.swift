import SwiftUI

/// A year of the user's work with agents as a graph, with the quiet game around it: the current and
/// longest streak, the busiest day and the year's total. Picking a day lists its tasks.
struct UsageActivityCard: View {
    let activity: ActivityLog
    /// What opens a task; nil when it can't be opened anymore.
    let opener: (ActivityDay.Task) -> (() -> Void)?

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
                    values: values.mapValues(\.value), estimated: Set(values.filter(\.value.isEstimate).keys),
                    endingOn: today,
                    selection: $selection, hovered: $hovered
                ) { day in
                    describe(day, values[day])
                }
                // A picked day heads its own task list; until then, the line says what's hovered.
                if let selection {
                    dayTasks(on: selection, values[selection])
                } else {
                    readout(values)
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
                label: "Count", selection: $metric,
                options: ActivityMetric.allCases.map { .init(value: $0, title: $0.title) },
                width: UsageMetrics.metricSelectWidth)
        }
    }

    private func stats(_ stats: ActivityStats) -> some View {
        HStack(alignment: .top, spacing: DS.Space.xxl) {
            stat("Current streak", days(stats.currentStreak))
            stat("Longest streak", days(stats.longestStreak))
            stat(
                "Busiest day",
                stats.busiest.map {
                    "\(shortDate($0.day)) · \(metric.describe($0.value))"
                } ?? "–")
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

    /// The hovered day in numbers, so the graph never relies on color alone.
    private func readout(_ values: [Date: (value: Double, isEstimate: Bool)]) -> some View {
        let day = hovered
        let text: String =
            if let day {
                describe(day, values[day])
                    + (values[day]?.isEstimate == true ? ", estimated from the agents’ session lists" : "")
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

    /// The picked day's tasks under one header: "Tuesday, October 13 · 21 prompts · 4 tasks".
    @ViewBuilder
    private func dayTasks(on day: Date, _ entry: (value: Double, isEstimate: Bool)?) -> some View {
        let tasks = activity.tasks(on: day, for: filter)
        let amount =
            entry.map { metric.describe($0.value, isEstimate: $0.isEstimate) } ?? "No \(metric.title.lowercased())"
        VStack(alignment: .leading, spacing: 0) {
            // An empty day says so in the line below, so the header doesn't count zero tasks.
            let count = tasks.isEmpty ? [] : [tasks.count == 1 ? "1 task" : "\(tasks.count) tasks"]
            ContributorSectionHeader(title: ([longDate(day), amount] + count).joined(separator: " · "), tokens: nil)
            if tasks.isEmpty {
                Text("No tasks that day.")
                    .font(.dsBody)
                    .foregroundStyle(.dsTextSecondary)
            }
            ForEach(tasks) { task in
                let detail = "\(task.agentName) · \(URL(filePath: task.project).lastPathComponent)"
                if let open = opener(task) {
                    HStack(spacing: DS.Space.md) {
                        ContributorRow(title: task.title ?? "Untitled task", detail: detail, tokens: nil)
                        Button("Open") {
                            open()
                            settings.close()
                        }
                        .buttonStyle(.ds(.secondary))
                        .help("Open this task")
                        .accessibilityLabel("Open \(task.title ?? "Untitled task")")
                    }
                    .padding(.vertical, DS.Space.xxs)
                } else {
                    ContributorRow(title: task.title ?? "Untitled task", detail: detail, tokens: "Not listed")
                        .help("\(task.agentName) no longer lists this task, so it can’t be opened.")
                }
            }
        }
    }

    /// "12 prompts on Tuesday, March 4"
    private func describe(_ day: Date, _ entry: (value: Double, isEstimate: Bool)?) -> String {
        let date = longDate(day)
        guard let entry else { return "No \(metric.title.lowercased()) on \(date)" }
        return "\(metric.describe(entry.value, isEstimate: entry.isEstimate)) on \(date)"
    }

    /// "Tuesday, October 13", with the year for last year's days, which share the graph with this
    /// year's.
    private func longDate(_ day: Date) -> String {
        withYearIfPast(day, .dateTime.weekday(.wide).month(.wide).day())
    }

    /// "Aug 3", or "Nov 3, 2025".
    private func shortDate(_ day: Date) -> String {
        withYearIfPast(day, .dateTime.month(.abbreviated).day())
    }

    private func withYearIfPast(_ day: Date, _ format: Date.FormatStyle) -> String {
        day.formatted(calendar.isDate(day, equalTo: .now, toGranularity: .year) ? format : format.year())
    }

    private func days(_ count: Int) -> String {
        count == 1 ? "1 day" : "\(count) days"
    }
}

#if NATIVE_PREVIEWS_WIP
#Preview("Activity") {
    DSPreviewPair {
        VStack(spacing: DS.Space.lg) {
            UsageActivityCard(activity: UsagePreviewFixtures.activity(), opener: { _ in {} })
            UsageActivityCard(activity: UsagePreviewFixtures.activity(empty: true), opener: { _ in nil })
        }
        .frame(width: 720)
    }
    .environment(SettingsPresentation())
}
#endif
