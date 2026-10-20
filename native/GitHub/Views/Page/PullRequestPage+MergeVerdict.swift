import GitHub
import SwiftUI

extension PullRequestPage {
    /// GitHub's merge verdict on an open, ready pull request, in its own words where it has them:
    /// "Ready to merge", "Has conflicts", "Queued · position 3". `nil` while GitHub is still working
    /// it out, and for drafts and closed or merged ones, which say so elsewhere.
    var mergeVerdict: (label: String, tint: Color)? {
        guard isOpen, !isDraft else { return nil }
        if mergeable == .conflicting { return ("Has conflicts", .dsDanger) }
        // A queue or auto-merge already arranged says where it stands, not whether it could merge.
        if let mergeState { return (mergeState.summary, .dsInfo) }
        return switch mergeStatus {
        case .clean, .hasHooks: (isMergeQueueEnabled ? "Ready for the merge queue" : "Ready to merge", .dsSuccess)
        case .unstable: ("Mergeable, some checks failed", .dsWarning)
        case .blocked: ("Blocked by branch protection", .dsWarning)
        case .behind: ("Behind \(baseRefName)", .dsWarning)
        case .dirty: ("Has conflicts", .dsDanger)
        case .draft, .unknown, .other, nil: nil
        }
    }
}
