import Foundation

/// What a session was doing when a usage limit stopped it, which decides what to send once the
/// limit resets. The session model knows which case it is: whether the turn got anywhere.
enum LimitedWork: Codable, Hashable, Sendable {
    /// The agent had started working when the limit cut the turn off.
    case interruptedTurn
    /// The prompt was refused before the agent did anything, so it goes out again as written.
    case unsentPrompt(String)

    static let continuationPrompt = "Continue where you left off."

    var resumePrompt: String {
        switch self {
        case .interruptedTurn: Self.continuationPrompt
        case .unsentPrompt(let prompt): prompt
        }
    }
}
