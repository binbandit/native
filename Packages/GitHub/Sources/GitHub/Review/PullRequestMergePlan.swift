import Foundation

/// What the merge control does for a pull request, decided from how its base branch merges: so the
/// button says exactly what clicking it does, and never reads as "merge now" when it queues or
/// waits.
///
/// - A base with a merge queue: "Merge When Ready" adds it to the queue, which merges it once the
///   queue's checks pass. Nothing merges at once, except for an admin who skips the queue (offered
///   apart, and confirmed).
/// - Auto-merge allowed, no queue: while requirements are pending, "Merge When Ready" turns on
///   auto-merge; once everything is green it merges directly.
/// - Neither: it merges directly when GitHub says it can, and says why when it can't.
public struct PullRequestMergePlan: Sendable, Hashable {
    public enum Route: Sendable, Hashable {
        case queue, autoMerge, direct
    }

    public enum Action: Sendable, Hashable {
        /// Adds it to the merge queue.
        case enqueue
        /// Turns on auto-merge with this method.
        case enableAutoMerge(MergeMethod)
        /// Merges now with this method.
        case merge(MergeMethod)
    }

    public let route: Route
    /// What the main button does; nil when nothing can be done now (`blocker` says why) or a merge is
    /// already arranged (`state`).
    public let action: Action?
    /// Why it can't merge, queue or auto-merge now.
    public let blocker: String?
    /// Worth knowing, but doesn't stop it.
    public let note: String?
    /// Queued or set to auto-merge, when it is.
    public let state: PullRequestMergeState?
    /// Why it last left the merge queue, while it isn't back in it.
    public let removedFromQueue: String?
    public let canDequeue: Bool
    public let canCancelAutoMerge: Bool
    /// An admin may merge now anyway, past the queue or unmet requirements, with this method.
    public let adminMerge: MergeMethod?
    /// The methods to choose between. Empty for a queue, which merges its own way.
    public let methods: [MergeMethod]
    /// The branch it merges into.
    public let base: String

    /// - Parameter method: The user's choice, when it's one of the repository's methods.
    public init(page: PullRequestPage, method: MergeMethod? = nil) {
        let allowed = page.mergeMethods
        let chosen =
            method.flatMap { allowed.contains($0) ? $0 : nil }
            ?? page.defaultMergeMethod.flatMap { allowed.contains($0) ? $0 : nil } ?? allowed.first ?? .merge
        let route: Route = page.isMergeQueueEnabled ? .queue : page.autoMergeAllowed ? .autoMerge : .direct
        let conflicts = page.mergeable == .conflicting || page.mergeStatus == .dirty
        var action: Action?
        var blocker: String?
        var note: String?
        var adminMerge: MergeMethod?

        if !page.isOpen {
            blocker = page.state == .merged ? "It's already merged." : "It's closed. Reopen it to merge."
        } else if page.isDraft {
            blocker = "Drafts can't merge. Mark it ready for review on GitHub first."
        } else if !page.viewerCanMerge {
            blocker = "Merging needs push access to \(page.reference.repository)."
        } else if page.mergeState != nil {
            // Already arranged: the state says how, and the plan offers taking it back.
        } else if conflicts {
            blocker = "This branch has conflicts with \(page.baseRefName). Resolve them first."
        } else {
            switch route {
            case .queue:
                action = .enqueue
                if page.viewerCanMergeAsAdmin { adminMerge = page.mergeQueueMethod ?? chosen }
            case .autoMerge, .direct:
                switch page.mergeStatus {
                case .clean, .hasHooks:
                    action = .merge(chosen)
                case .unstable:
                    action = .merge(chosen)
                    note = "Some checks failed. They aren't required, so it can still merge."
                case .unknown, nil:
                    blocker = "GitHub is still working out whether it can merge. Check again in a moment."
                default:
                    if route == .autoMerge, page.viewerCanEnableAutoMerge, page.mergeStatus != .behind {
                        action = .enableAutoMerge(chosen)
                    } else {
                        blocker = Self.waiting(page)
                    }
                    if page.viewerCanMergeAsAdmin { adminMerge = chosen }
                }
            }
        }

        self.route = route
        self.action = action
        self.blocker = blocker
        self.note = note
        state = page.mergeState
        removedFromQueue = page.mergeState == nil && route == .queue ? page.removedFromQueueReason : nil
        canDequeue = page.isOpen && page.viewerCanMerge && Self.isQueued(page.mergeState)
        canCancelAutoMerge = page.isOpen && page.viewerCanDisableAutoMerge && Self.isAutoMerge(page.mergeState)
        self.adminMerge = adminMerge
        methods = route == .queue ? [] : allowed
        base = page.baseRefName
    }

    /// The main button's title: "Merge When Ready", or exactly how it merges now.
    public var title: String {
        switch action {
        case .enqueue, .enableAutoMerge: "Merge When Ready"
        case .merge(let method): "\(Self.verb(method)) into \(base)"
        case nil: "Merge"
        }
    }

    /// What clicking the main button does, in a sentence.
    public var explanation: String? {
        switch action {
        case .enqueue:
            "Adds it to \(base)'s merge queue, which merges it once the queue's checks pass. Nothing merges right now."
        case .enableAutoMerge(let method):
            "Turns on auto-merge: GitHub will \(Self.verb(method).lowercased()) it into \(base) once required checks and reviews pass. Nothing merges right now."
        case .merge(let method):
            "\(Self.sentence(method)) into \(base) now."
        case nil:
            nil
        }
    }

    /// "Squash and Merge", "Rebase and Merge", "Merge".
    public static func verb(_ method: MergeMethod) -> String {
        switch method {
        case .merge: "Merge"
        case .squash: "Squash and Merge"
        case .rebase: "Rebase and Merge"
        }
    }

    private static func sentence(_ method: MergeMethod) -> String {
        switch method {
        case .merge: "Merges it with a merge commit"
        case .squash: "Squashes its commits into one and merges it"
        case .rebase: "Rebases its commits and merges them"
        }
    }

    private static func waiting(_ page: PullRequestPage) -> String {
        switch page.mergeStatus {
        case .behind: "This branch is behind \(page.baseRefName), which must be up to date first."
        case .draft: "Drafts can't merge. Mark it ready for review on GitHub first."
        default: "Branch protection blocks this merge: it needs approvals or passing required checks."
        }
    }

    private static func isQueued(_ state: PullRequestMergeState?) -> Bool {
        if case .queued? = state { true } else { false }
    }

    private static func isAutoMerge(_ state: PullRequestMergeState?) -> Bool {
        if case .autoMerge? = state { true } else { false }
    }
}
