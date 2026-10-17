import Foundation

/// A session `ContextReports` can ask for a `/context` report. `SessionModel` conforms.
protocol ContextReporting: AnyObject {
    var contextKey: SessionKey { get }
    /// Whether the agent answers `/context` with a report. Only Claude Code does today; the others
    /// have no such command, so this follows the commands each agent advertises.
    var canReportContext: Bool { get }
    /// Whether a hidden command can run now without waiting for a turn.
    var isIdleForContext: Bool { get }
    func runHiddenCommand(_ command: String) async throws -> String
}
