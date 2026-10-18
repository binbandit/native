import ACP
import Foundation
import Observation

/// Per-day activity for Settings › Usage's graph: prompts, turns, tokens, cost and agent time by
/// agent and project, plus the tasks touched each day. Days are local calendar days, kept as the
/// date they were recorded on, so travelling doesn't move them.
@Observable
final class ActivityLog {
    /// A little over a year, so the graph always has its 53 weeks.
    static let retainedDays = 400

    private(set) var days: [String: ActivityDay]

    @ObservationIgnored private let store: any ActivityStore
    @ObservationIgnored private let now: () -> Date
    /// Each session's last usage this run, to turn running totals into what a day added.
    @ObservationIgnored private var lastUsage: [String: (used: Int, cost: Double)] = [:]
    /// Sessions created this run: their first usage report is all new. A reopened one's first report
    /// carries what earlier runs already spent, so it only sets the baseline.
    @ObservationIgnored private var startedThisRun: Set<String> = []
    @ObservationIgnored private var pendingSave: Task<Void, Never>?

    init(store: any ActivityStore, now: @escaping () -> Date = Date.init) {
        self.store = store
        self.now = now
        days = Dictionary(store.load().map { ($0.day, $0) }) { $1 }
    }

    // MARK: - Recording

    func recordSessionStarted(_ context: SessionContext) {
        startedThisRun.insert(Self.sessionKey(context))
    }

    func recordPrompt(_ context: SessionContext) {
        record(context) { $0.prompts += 1 }
    }

    func recordTurn(_ context: SessionContext, duration: TimeInterval?) {
        record(context) { counts in
            counts.turns += 1
            counts.activeSeconds += duration ?? 0
        }
    }

    func recordUsage(_ context: SessionContext, _ usage: Usage) {
        let key = Self.sessionKey(context)
        let cost = usage.cost.flatMap { $0.currency == "USD" ? $0.amount : nil } ?? 0
        let previous = lastUsage[key] ?? (startedThisRun.contains(key) ? (0, 0) : nil)
        lastUsage[key] = (usage.used, cost)
        guard let previous else { return }
        let tokens = max(usage.used - previous.used, 0)
        let spent = max(cost - previous.cost, 0)
        guard tokens > 0 || spent > 0 else { return }
        record(context, touchesTask: false) { counts in
            counts.tokens += tokens
            counts.cost += spent
        }
    }

    /// The sessions the agents list now, for `refreshBackfill()`; the app sets it.
    @ObservationIgnored var backfillSource: (() -> [ActivityBackfill])?

    /// Fills in what the agents list now. Their lists grow as they start and list more projects,
    /// so this runs at launch and again whenever the graph is shown.
    func refreshBackfill() {
        if let sessions = backfillSource?() {
            backfill(sessions)
        }
    }

    /// Fills in sessions the agents list as estimates: one per session on the day it was last
    /// active. Running it again changes nothing.
    func backfill(_ sessions: [ActivityBackfill]) {
        let cutoff = now().addingTimeInterval(-Double(Self.retainedDays) * 86_400)
        let grouped = Dictionary(grouping: sessions.filter { $0.updatedAt > cutoff }) { session in
            "\(dayKey(for: session.updatedAt))|\(session.agent)|\(session.project)"
        }
        var changed = false
        for group in grouped.values {
            guard let first = group.first else { continue }
            let key = dayKey(for: first.updatedAt)
            var day = days[key] ?? ActivityDay(day: key)
            let current = day.entries.first { $0.agent == first.agent && $0.project == first.project }?.counts.listedSessions ?? 0
            if group.count > current {
                day.add(ActivityCounts(listedSessions: group.count - current), agent: first.agent, agentName: first.agentName, project: first.project)
                changed = true
            }
            for session in group {
                day.touch(.init(agent: session.agent, agentName: session.agentName, session: session.session, title: session.title, project: session.project))
            }
            days[key] = day
        }
        if changed {
            scheduleSave()
        }
    }

    private func record(_ context: SessionContext, touchesTask: Bool = true, change: (inout ActivityCounts) -> Void) {
        let key = dayKey(for: now())
        var day = days[key] ?? ActivityDay(day: key)
        var counts = ActivityCounts()
        change(&counts)
        let project = context.cwd.path(percentEncoded: false)
        day.add(counts, agent: context.agent.rawValue, agentName: context.agentName, project: project)
        if touchesTask, let session = context.sessionID, context.parentID == nil {
            day.touch(.init(agent: context.agent.rawValue, agentName: context.agentName, session: session.rawValue, title: context.title, project: project))
        }
        days[key] = day
        scheduleSave()
    }

    // MARK: - Reading

    /// Each day's value for the graph, by the day's local start, with whether it's only estimated.
    func values(of metric: ActivityMetric, for filter: ActivityFilter) -> [Date: (value: Double, isEstimate: Bool)] {
        var values: [Date: (value: Double, isEstimate: Bool)] = [:]
        for day in days.values {
            guard let date = date(forKey: day.day) else { continue }
            let counts = self.counts(in: day, for: filter)
            let value = metric.value(of: counts)
            if value > 0 {
                values[date] = (value, metric == .prompts && counts.isEstimate)
            }
        }
        return values
    }

    func counts(on date: Date, for filter: ActivityFilter) -> ActivityCounts {
        days[dayKey(for: date)].map { counts(in: $0, for: filter) } ?? ActivityCounts()
    }

    func tasks(on date: Date, for filter: ActivityFilter) -> [ActivityDay.Task] {
        days[dayKey(for: date)]?.tasks.filter(filter.includes) ?? []
    }

    /// The agents and projects with any activity, for the graph's filter: (id, name).
    var agents: [(id: String, name: String)] {
        let pairs = days.values.flatMap(\.entries).map { ($0.agent, $0.agentName) }
        return Dictionary(pairs) { first, _ in first }.map { (id: $0.key, name: $0.value) }.sorted { $0.name < $1.name }
    }

    var projects: [(id: String, name: String)] {
        Set(days.values.flatMap(\.entries).map(\.project))
            .map { (id: $0, name: URL(filePath: $0).lastPathComponent) }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    private func counts(in day: ActivityDay, for filter: ActivityFilter) -> ActivityCounts {
        day.entries.filter(filter.includes).reduce(ActivityCounts()) { $0 + $1.counts }
    }

    // MARK: - Days

    func dayKey(for date: Date) -> String {
        date.formatted(Date.ISO8601FormatStyle(timeZone: .current).year().month().day())
    }

    /// The key's day in the calendar now in use.
    func date(forKey key: String) -> Date? {
        let parts = key.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        return Calendar.current.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2]))
    }

    private static func sessionKey(_ context: SessionContext) -> String {
        "\(context.agent.rawValue)/\(context.sessionID?.rawValue ?? context.clientID.uuidString)"
    }

    // MARK: - Saving

    /// Batched, since a busy turn reports usage often.
    private func scheduleSave() {
        pendingSave?.cancel()
        pendingSave = Task { [weak self] in
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled, let self else { return }
            self.save()
        }
    }

    func save() {
        let oldest = dayKey(for: now().addingTimeInterval(-Double(Self.retainedDays) * 86_400))
        store.save(days.values.filter { $0.day >= oldest }.sorted { $0.day < $1.day })
    }
}
