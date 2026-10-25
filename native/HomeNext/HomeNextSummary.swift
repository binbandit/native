import Foundation

/// What Home can add beyond its asks, each the user's own choice. All are off in the calm default.
enum HomeNextSummary: String, CaseIterable, Identifiable {
    /// GitHub pull requests waiting on the user's review, as one row in Up next.
    case reviews
    /// An agent paused at its usage limit, as one row in Up next until it resets.
    case usageLimits
    /// What happened while the user was away, as one line under Up next.
    case away

    var id: Self { self }

    /// Read with `@AppStorage(summary.storageKey)`, defaulting to false.
    var storageKey: String { "homeNext.shows.\(rawValue)" }

    var title: String {
        switch self {
        case .reviews: "Review requests"
        case .usageLimits: "Usage limits"
        case .away: "While you were away"
        }
    }

    var detail: String {
        switch self {
        case .reviews: "Pull requests waiting on your review join Up next."
        case .usageLimits: "An agent paused at its usage limit joins Up next until the limit resets."
        case .away: "One line sums up what finished, asked for you or failed while you were away."
        }
    }

    func isShown(in defaults: UserDefaults = .standard) -> Bool {
        defaults.bool(forKey: storageKey)
    }
}
