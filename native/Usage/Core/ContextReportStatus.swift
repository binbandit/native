import Foundation

/// Where a session's context breakdown stands.
enum ContextReportStatus: Hashable {
    /// The agent can't break its context down; only totals are known.
    case unsupported
    /// A report can be taken now. `isStale` says the last one predates the latest turn.
    case ready(isStale: Bool)
    /// The agent is working; a report can be taken once it's idle.
    case busy
    case refreshing
    case failed

    var canRefresh: Bool {
        if case .ready = self { true } else { self == .failed }
    }
}
