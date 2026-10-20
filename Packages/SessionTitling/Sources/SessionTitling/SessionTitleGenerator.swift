/// Writes a short title for a task from what the user asked for.
public protocol SessionTitleGenerator: Sendable {
    /// Returns nil when it can't write one here right now (no model on this machine, say), so
    /// someone else may; throws when it tried and failed.
    func title(for request: SessionTitleRequest) async throws -> String?
}
