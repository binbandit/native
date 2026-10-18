import Foundation

/// What submitting a review says.
public enum ReviewEvent: String, Sendable, Hashable, CaseIterable {
    case comment = "COMMENT"
    case approve = "APPROVE"
    case requestChanges = "REQUEST_CHANGES"
}
