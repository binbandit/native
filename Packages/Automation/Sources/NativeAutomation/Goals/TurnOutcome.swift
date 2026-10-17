import Foundation

/// How an agent's turn ended, as goals and workflow steps see it. The app maps ACP stop reasons and
/// prompt errors onto this, so the engines stay free of protocol types.
public nonisolated enum TurnOutcome: Codable, Hashable, Sendable {
    /// The agent finished its turn on its own.
    case ended
    /// The user, or Native on their behalf, stopped the turn.
    case cancelled
    /// The provider cut the turn short: token, request, rate or usage limits. Retrying right away
    /// would hit the same wall, so loops stop instead.
    case limited(String)
    /// The agent declined to continue.
    case refused
    /// The turn errored, or the agent went away.
    case failed(String)

    /// Classifies a prompt that failed with `message`. Providers report their limits as errors, and
    /// a limit has to read as one: a goal that treats it as a failure would be resumed into the same
    /// limit, and one that ignores it would spin.
    public static func failure(_ message: String) -> TurnOutcome {
        let lowered = message.lowercased()
        return limitPhrases.contains(where: lowered.contains) ? .limited(message) : .failed(message)
    }

    private static let limitPhrases = [
        "rate limit", "rate_limit", "ratelimit", "usage limit", "usage_limit", "quota", "credit balance",
        "out of credits", "insufficient credits", "limit reached", "limit exceeded", "too many requests",
        "429", "overloaded",
    ]
}
