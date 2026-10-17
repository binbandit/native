import Foundation

/// Everything `UsageLimits` keeps across launches: scheduled resumes have to fire even if Native
/// was quit in between.
struct UsageLimitsSnapshot: Codable, Equatable {
    var providers: [ProviderLimit] = []
    var sessions: [LimitedSession] = []
}
