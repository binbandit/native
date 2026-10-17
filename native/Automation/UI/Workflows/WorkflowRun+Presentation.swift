import Foundation

extension WorkflowRun {
    /// The run's status in a word or two. A run that stopped short says how, since "stopped" alone
    /// doesn't tell the user whether to retry, wait for a reset or move on.
    var statusLabel: String {
        guard phase == .halted else { return phase.label }
        if steps.contains(where: { if case .failed = $0.status { true } else { false } }) { return "Step failed" }
        if steps.contains(where: { $0.status == .interrupted }) { return "Interrupted" }
        if steps.contains(where: { if case .limited = $0.status { true } else { false } }) { return "Limited" }
        return "Step stopped"
    }

    var hasFailedStep: Bool {
        steps.contains { if case .failed = $0.status { true } else { false } }
    }

    /// "started 5m ago", or "started just now".
    func startedText(now: Date) -> String {
        let age = DSFormat.compactAge(createdAt, now: now)
        return age == "now" ? "started just now" : "started \(age) ago"
    }
}
