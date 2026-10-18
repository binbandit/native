import Foundation

/// What happened in one day, for one agent in one project. Aggregates only, never single events.
struct ActivityCounts: Codable, Hashable {
    var prompts = 0
    var turns = 0
    /// Tokens added to the context window, as the agent's usage updates report it.
    var tokens = 0
    /// Spend in US dollars, from the agent's own cost estimates.
    var cost = 0.0
    /// Time agents spent working on turns.
    var activeSeconds = 0.0
    /// Sessions the agent's list says were active that day, for days before Native recorded any.
    var listedSessions = 0

    static func + (lhs: Self, rhs: Self) -> Self {
        ActivityCounts(
            prompts: lhs.prompts + rhs.prompts, turns: lhs.turns + rhs.turns, tokens: lhs.tokens + rhs.tokens,
            cost: lhs.cost + rhs.cost, activeSeconds: lhs.activeSeconds + rhs.activeSeconds,
            listedSessions: lhs.listedSessions + rhs.listedSessions)
    }

    /// Nothing recorded first-hand, only what the session list implies.
    var isEstimate: Bool {
        prompts == 0 && turns == 0 && tokens == 0 && cost == 0 && activeSeconds == 0 && listedSessions > 0
    }
}
