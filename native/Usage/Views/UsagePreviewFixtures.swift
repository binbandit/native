#if DEBUG
import ACP
import SwiftUI

/// A context source with fixed numbers, for previews.
struct PreviewContextSource: ContextSource {
    var agentName = "Claude Code"
    var usage: Usage?
    var report: ContextReport?
    var reportStatus: ContextReportStatus = .ready(isStale: false)
    var canCompact = true
    var isAwaitingContextUsage = false

    func refreshReport() async {}
    func compact() async {}

    static func claude(used: Int) -> PreviewContextSource {
        PreviewContextSource(
            usage: usage(used: used, size: 1_000_000, cost: 0.19),
            report: ContextReport.parse(sampleReport(messages: used - 228_390))
        )
    }

    static let codex = PreviewContextSource(
        agentName: "Codex", usage: usage(used: 61_200, size: 258_400), reportStatus: .unsupported, canCompact: false
    )

    static let compacted = PreviewContextSource(
        agentName: "Codex", reportStatus: .unsupported, canCompact: true, isAwaitingContextUsage: true
    )

    /// Decoded as an agent would send it: `Usage` has no public initializer.
    static func usage(used: Int, size: Int, cost: Double? = nil) -> Usage? {
        let cost = cost.map { #","cost":{"amount":\#($0),"currency":"USD"}"# } ?? ""
        return try? JSONDecoder().decode(Usage.self, from: Data(#"{"used":\#(used),"size":\#(size)\#(cost)}"#.utf8))
    }

    /// Shaped like Claude Code's answer to `/context`, trimmed.
    static func sampleReport(messages: Int) -> String {
        let free = max(1_000_000 - 228_390 - messages - 33_000, 0)
        return """
            ## Context Usage

            **Model:** claude-opus-5-5
            **Tokens:** \(DSFormat.tokens(228_390 + messages)) / 1m

            ### Estimated usage by category

            | Category | Tokens | Percentage |
            |----------|--------|------------|
            | System prompt | 2.1k | 0.2% |
            | System tools | 23.1k | 2.3% |
            | MCP tools | 197.1k | 19.7% |
            | Memory files | 2k | 0.2% |
            | Skills | 4k | 0.4% |
            | Messages | \(DSFormat.tokens(max(messages, 10))) | 0% |
            | Free space | \(DSFormat.tokens(free)) | 0% |
            | Autocompact buffer | 33k | 3.3% |

            ### MCP Tools

            | Tool | Server | Tokens |
            |------|--------|--------|
            | mcp__linear__list_issues | linear | 112.4k |
            | mcp__linear__create_issue | linear | 41k |
            | mcp__github__search_code | github | 43.7k |

            ### Memory Files

            | Type | Path | Tokens |
            |------|------|--------|
            | Project | /Users/preview/Developer/native/AGENTS.md | 2k |

            ### Skills

            | Skill | Source | Tokens |
            |-------|--------|--------|
            | dataviz | Built-in | ~480 |
            | review | User | ~70 |
            """
    }
}
#endif

#if NATIVE_PREVIEWS_WIP
/// Limits, provider readings and a year of activity for Usage's previews, all kept in memory.
enum UsagePreviewFixtures {
    static let claude = AgentDefinition.ID(rawValue: "claude-code")
    static let codex = AgentDefinition.ID(rawValue: "codex")
    static let limitedSession = SessionID("0199f3a2-queue")

    /// Claude Code at its 5-hour limit (stopping one task, which can resume at the reset), and Codex
    /// close to its weekly one.
    static func limits(resumeScheduled: Bool = false) -> UsageLimits {
        let now = Date.now
        let target = UsageSessionRef(
            agent: claude, agentName: "Claude Code", session: limitedSession,
            title: "Queue follow-ups while a turn runs")
        let snapshot = UsageLimitsSnapshot(
            providers: [
                ProviderLimit(
                    agent: claude, agentName: "Claude Code", status: .reached, window: .fiveHour,
                    resetsAt: now.addingTimeInterval(42 * 60), utilization: 1, updatedAt: now),
                ProviderLimit(
                    agent: codex, agentName: "Codex", status: .warning, window: .sevenDay,
                    resetsAt: now.addingTimeInterval(3 * 86_400), utilization: 0.9, updatedAt: now),
            ],
            sessions: [
                LimitedSession(
                    target: target, work: .interruptedTurn,
                    resumeAt: resumeScheduled ? now.addingTimeInterval(42 * 60 + UsageLimits.resetMargin) : nil)
            ])
        return UsageLimits(store: PreviewLimitsStore(snapshot: snapshot), alerts: PreviewLimitAlerts())
    }

    /// No limit in sight.
    static func clearLimits() -> UsageLimits {
        UsageLimits(store: PreviewLimitsStore(snapshot: UsageLimitsSnapshot()), alerts: PreviewLimitAlerts())
    }

    /// The windows each agent's own status command reported.
    static let reports = ProviderUsageReports(reports: [
        claude: ProviderUsageReport(
            windows: [
                .init(name: "Current session", utilization: 0.62, resetsAt: .now.addingTimeInterval(3 * 3600)),
                .init(
                    name: "Current week (all models)", utilization: 0.41, resetsAt: .now.addingTimeInterval(3 * 86_400)),
                .init(name: "Current week (Opus)", utilization: 0.88, resetsAt: .now.addingTimeInterval(3 * 86_400)),
            ], capturedAt: .now.addingTimeInterval(-4 * 60)),
        codex: ProviderUsageReport(
            windows: [
                .init(name: "5h limit", utilization: 0.3, resetsAt: .now.addingTimeInterval(2 * 3600)),
                .init(name: "Weekly limit", utilization: 0.55, resetsAt: .now.addingTimeInterval(5 * 86_400)),
            ], capturedAt: .now.addingTimeInterval(-50 * 60)),
    ])

    /// A year of work: busier on weekdays, a quiet stretch in the summer, a few estimated days early on.
    static func activity(empty: Bool = false) -> ActivityLog {
        ActivityLog(store: PreviewActivityStore(days: empty ? [] : year))
    }

    private static let year: [ActivityDay] = {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)
        let projects = ["/Users/preview/Developer/native", "/Users/preview/Developer/pier"]
        return (0..<365).compactMap { offset -> ActivityDay? in
            guard let date = calendar.date(byAdding: .day, value: -offset, to: today) else { return nil }
            let weekday = calendar.component(.weekday, from: date)
            // A repeatable spread rather than randomness, so the preview looks the same every time.
            let seed = (offset * 37 + 11) % 23
            let isWeekend = weekday == 1 || weekday == 7
            let prompts = isWeekend ? seed % 4 : (seed > 2 ? seed + 3 : 0)
            guard prompts > 0, !(150...170).contains(offset) else { return nil }
            var day = ActivityDay(day: date.formatted(Date.ISO8601FormatStyle(timeZone: .current).year().month().day()))
            let counts =
                offset > 330
                ? ActivityCounts(listedSessions: max(prompts / 4, 1))
                : ActivityCounts(
                    prompts: prompts, turns: prompts + 2, tokens: prompts * 41_000, cost: Double(prompts) * 0.37,
                    activeSeconds: Double(prompts) * 140)
            day.add(
                counts, agent: offset % 3 == 0 ? "codex" : "claude-code",
                agentName: offset % 3 == 0 ? "Codex" : "Claude Code", project: projects[offset % 2])
            if offset < 3 {
                day.touch(
                    ActivityDay.Task(
                        agent: "claude-code", agentName: "Claude Code", session: "0199f3a2-queue",
                        title: "Queue follow-ups while a turn runs", project: projects[0]))
                day.touch(
                    ActivityDay.Task(
                        agent: "codex", agentName: "Codex", session: "0199f3a2-flaky",
                        title: "Fix flaky permission request test", project: projects[0]))
            }
            return day
        }
    }()

    /// Where Claude Code's turn stopped on its limit, as the transcript shows it.
    static let limitStop: UsageLimitStop? = {
        var state = SessionState()
        state.appendUserMessage("Queue follow-ups while a turn runs")
        state.appendNotice("You've hit your session limit · resets 3:05pm (Australia/Sydney)", isError: true)
        return UsageLimitStop(turnItems: state.items, stopReason: .error)
    }()

    /// A Claude Code breakdown, as `ContextBreakdownView` reads it.
    static let report = PreviewContextSource.claude(used: 480_000).report
}

/// Keeps the limits snapshot in memory; nothing is saved.
final class PreviewLimitsStore: UsageLimitsStore {
    private let snapshot: UsageLimitsSnapshot

    init(snapshot: UsageLimitsSnapshot) {
        self.snapshot = snapshot
    }

    func load() -> UsageLimitsSnapshot { snapshot }
    func save(_ snapshot: UsageLimitsSnapshot) {}
}

/// Posts nothing: previews never notify.
final class PreviewLimitAlerts: LimitAlerting {
    var onAction: ((LimitAlertAction) -> Void)?

    func post(_ alert: LimitAlert) async {}
}

/// Keeps activity days in memory; nothing is saved.
struct PreviewActivityStore: ActivityStore {
    let days: [ActivityDay]

    func load() -> [ActivityDay] { days }
    func save(_ days: [ActivityDay]) {}
}
#endif
