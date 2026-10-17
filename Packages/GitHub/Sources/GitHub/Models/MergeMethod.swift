import Foundation

public enum MergeMethod: String, Sendable, Hashable, CaseIterable {
    case merge, squash, rebase
}
