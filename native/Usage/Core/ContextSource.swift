import ACP
import Foundation

/// What the context indicator and breakdown read: a session's totals and, from agents that can
/// give one, its breakdown.
protocol ContextSource {
    var agentName: String { get }
    /// Totals from the agent's usage updates.
    var usage: Usage? { get }
    var report: ContextReport? { get }
    var reportStatus: ContextReportStatus { get }
    func refreshReport() async
}

extension ContextSource {
    /// The used share of the window, from the freshest numbers available. Usage updates follow
    /// every turn; a report can be older.
    var fractionUsed: Double? {
        if let usage, usage.size > 0 { return usage.fractionUsed }
        return report?.fractionUsed
    }
}
