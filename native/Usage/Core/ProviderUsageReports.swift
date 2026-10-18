import ACP
import Foundation
import Observation

/// Each provider's limit windows, read with the agent's own status command (Claude Code's
/// `/usage`, Codex's `/status`) in one of its idle tasks. The commands run hidden and cost nothing.
@Observable
final class ProviderUsageReports {
    private(set) var reports: [AgentDefinition.ID: ProviderUsageReport] = [:]
    private var refreshing: Set<AgentDefinition.ID> = []
    private var failed: Set<AgentDefinition.ID> = []
    @ObservationIgnored weak var host: (any UsageReportingHost)?

    /// `reports` seeds readings, for previews.
    init(reports: [AgentDefinition.ID: ProviderUsageReport] = [:]) {
        self.reports = reports
    }

    enum Status: Hashable {
        /// No idle task of the agent to ask, or it has no status command.
        case unavailable
        case ready
        case refreshing
        /// The agent answered without any limit windows.
        case unreported
    }

    func status(of agent: AgentDefinition.ID) -> Status {
        if refreshing.contains(agent) { return .refreshing }
        guard let session = host?.reportingSession(for: agent), Self.command(for: session) != nil else {
            return .unavailable
        }
        return failed.contains(agent) ? .unreported : .ready
    }

    func refresh(_ agent: AgentDefinition.ID) async {
        guard !refreshing.contains(agent), let session = host?.reportingSession(for: agent),
            let command = Self.command(for: session)
        else { return }
        refreshing.insert(agent)
        defer { refreshing.remove(agent) }
        if let text = try? await session.runHiddenCommand(command), let report = ProviderUsageReport.parse(text) {
            reports[agent] = report
            failed.remove(agent)
        } else {
            failed.insert(agent)
        }
    }

    /// The agent's open tasks with what they've used so far.
    func taskUsage(of agent: AgentDefinition.ID) -> [UsageTaskSpend] {
        host?.taskUsage(of: agent) ?? []
    }

    /// Chosen by the commands the agent advertises, never by which agent it is.
    static func command(for session: any ContextReporting) -> String? {
        ["usage", "status"].first(where: session.advertises).map { "/\($0)" }
    }
}
