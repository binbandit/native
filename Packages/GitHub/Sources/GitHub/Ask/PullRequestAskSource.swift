import Foundation

/// What a private question about a pull request can draw on: the pull request as its page loaded
/// it, the conversation, the review threads, and each changed file with its diff where GitHub sent
/// one. Plain values, so the budget rules in `PullRequestAskContext` are tested without GitHub.
public struct PullRequestAskSource: Sendable, Hashable {
    /// A conversation comment, or a review's summary.
    public struct Comment: Sendable, Hashable {
        public enum Kind: Sendable, Hashable {
            case comment
            case review(PullRequestReview.State)
        }

        public var kind: Kind
        public var author: String?
        public var body: String
        public var date: Date?

        public init(kind: Kind = .comment, author: String?, body: String, date: Date? = nil) {
            self.kind = kind
            self.author = author
            self.body = body
            self.date = date
        }
    }

    /// A conversation on lines of a file.
    public struct Thread: Sendable, Hashable {
        public struct Note: Sendable, Hashable {
            public var author: String?
            public var body: String

            public init(author: String?, body: String) {
                self.author = author
                self.body = body
            }
        }

        public var path: String
        /// The line on the current diff, or where it was written once outdated.
        public var line: Int?
        public var isResolved: Bool
        public var isOutdated: Bool
        public var notes: [Note]
        /// The diff around the first comment when it was written, ending at its line.
        public var diffHunk: String

        public init(
            path: String, line: Int?, isResolved: Bool = false, isOutdated: Bool = false, notes: [Note],
            diffHunk: String = ""
        ) {
            self.path = path
            self.line = line
            self.isResolved = isResolved
            self.isOutdated = isOutdated
            self.notes = notes
            self.diffHunk = diffHunk
        }
    }

    public struct File: Sendable, Hashable {
        public enum Diff: Sendable, Hashable {
            case patch(String)
            /// GitHub sent no patch: binary, too large to show, or only renamed.
            case missing(FilePatch.MissingPatchReason)
            /// Past the pages of patches Native loaded.
            case notLoaded
        }

        public var path: String
        public var previousPath: String?
        public var changeType: ChangedFile.ChangeType
        public var additions: Int
        public var deletions: Int
        public var diff: Diff

        public init(
            path: String, previousPath: String? = nil, changeType: ChangedFile.ChangeType = .modified,
            additions: Int, deletions: Int, diff: Diff
        ) {
            self.path = path
            self.previousPath = previousPath
            self.changeType = changeType
            self.additions = additions
            self.deletions = deletions
            self.diff = diff
        }

        public var isGenerated: Bool {
            GeneratedFiles.isGenerated(path)
        }

        public var patch: String? {
            if case .patch(let patch) = diff { patch } else { nil }
        }
    }

    public var reference: PullRequestReference
    public var title: String
    public var author: String?
    public var state: PullRequest.State
    public var isDraft: Bool
    public var baseRefName: String
    public var headRefName: String
    public var headRefOid: String
    public var additions: Int
    public var deletions: Int
    public var labels: [String]
    public var reviewDecision: PullRequest.ReviewDecision?
    public var checks: CheckSummary?
    public var body: String
    public var comments: [Comment]
    /// Whether the conversation goes on past what was loaded.
    public var hasMoreConversation: Bool
    public var threads: [Thread]
    /// How many review threads GitHub has, loaded or not.
    public var threadsTotal: Int
    public var files: [File]
    /// How many files the pull request changes, listed or not.
    public var filesTotal: Int

    public init(
        reference: PullRequestReference, title: String, author: String? = nil, state: PullRequest.State = .open,
        isDraft: Bool = false, baseRefName: String = "main", headRefName: String, headRefOid: String,
        additions: Int? = nil, deletions: Int? = nil, labels: [String] = [],
        reviewDecision: PullRequest.ReviewDecision? = nil, checks: CheckSummary? = nil, body: String = "",
        comments: [Comment] = [], hasMoreConversation: Bool = false, threads: [Thread] = [],
        threadsTotal: Int? = nil, files: [File] = [], filesTotal: Int? = nil
    ) {
        self.reference = reference
        self.title = title
        self.author = author
        self.state = state
        self.isDraft = isDraft
        self.baseRefName = baseRefName
        self.headRefName = headRefName
        self.headRefOid = headRefOid
        self.additions = additions ?? files.reduce(0) { $0 + $1.additions }
        self.deletions = deletions ?? files.reduce(0) { $0 + $1.deletions }
        self.labels = labels
        self.reviewDecision = reviewDecision
        self.checks = checks
        self.body = body
        self.comments = comments
        self.hasMoreConversation = hasMoreConversation
        self.threads = threads
        self.threadsTotal = threadsTotal ?? threads.count
        self.files = files
        self.filesTotal = filesTotal ?? files.count
    }
}

extension PullRequestAskSource {
    /// The pull request as its page loaded it. `files` is every file listed so far (the page lists
    /// a hundred, later pages the rest) and `patches` the diffs fetched so far, by path; a listed
    /// file without one is `.notLoaded`.
    public init(page: PullRequestPage, files: [ChangedFile], patches: [String: FilePatch]) {
        let comments = page.timeline.compactMap { item -> Comment? in
            switch item {
            case .comment(let comment):
                return Comment(author: comment.author, body: comment.body, date: comment.createdAt)
            case .review(let review):
                // A plain "commented" review with no summary says nothing here; its lines are threads.
                guard !review.body.isEmpty || review.state != .commented else { return nil }
                return Comment(
                    kind: .review(review.state), author: review.author, body: review.body, date: review.submittedAt)
            case .commit, .event, .other:
                return nil
            }
        }
        let threads = page.threads.map { thread in
            Thread(
                path: thread.path, line: thread.line ?? thread.originalLine, isResolved: thread.isResolved,
                isOutdated: thread.isOutdated,
                notes: thread.comments.map { Thread.Note(author: $0.author, body: $0.body) },
                diffHunk: thread.comments.first?.diffHunk ?? "")
        }
        let listed = files.isEmpty ? page.files : files
        let askFiles = listed.map { file in
            let patch = patches[file.path]
            let diff: File.Diff =
                if let patch {
                    patch.patch.map(File.Diff.patch) ?? patch.missingPatchReason.map(File.Diff.missing) ?? .notLoaded
                } else {
                    .notLoaded
                }
            return File(
                path: file.path, previousPath: patch?.previousPath, changeType: file.changeType,
                additions: file.additions, deletions: file.deletions, diff: diff)
        }
        self.init(
            reference: page.reference, title: page.title, author: page.author, state: page.state,
            isDraft: page.isDraft, baseRefName: page.baseRefName, headRefName: page.headRefName,
            headRefOid: page.headRefOid, additions: page.additions, deletions: page.deletions,
            labels: page.labels.map(\.name), reviewDecision: page.reviewDecision, checks: page.checks,
            body: page.body, comments: comments, hasMoreConversation: page.timelineCursor != nil,
            threads: threads, threadsTotal: page.threadsTotal, files: askFiles,
            filesTotal: max(page.changedFiles, askFiles.count))
    }
}
