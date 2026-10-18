import Foundation

/// Which side of a diff a review comment is on: the base (removed lines) or the head (added and
/// unchanged lines).
public enum DiffSide: String, Sendable, Hashable, Codable, GitHubEnum {
    case left = "LEFT"
    case right = "RIGHT"
    case other
}
