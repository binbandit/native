import Foundation

/// Which pull request a command acts on; gh accepts any of these as its argument.
public enum PullRequestSelector: Sendable, Hashable {
    case number(Int)
    /// A pull request's web URL, which works without a local checkout.
    case url(URL)
    /// The pull request whose head is this branch.
    case branch(String)

    var argument: String {
        switch self {
        case .number(let number): String(number)
        case .url(let url): url.absoluteString
        case .branch(let branch): branch
        }
    }
}
