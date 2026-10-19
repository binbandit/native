import Foundation

/// What an agent is told about the pull request its task checked out: which one and where it's
/// going, its description, how this checkout pushes to it, and optionally what reviewers asked
/// for. Written as Markdown and attached to the task's first message.
public struct PullRequestTaskBrief: Sendable, Hashable {
    public var pullRequest: PullRequestDetails
    /// The local branch the head is checked out on.
    public var branch: String
    /// How to push to the pull request from the checkout; `nil` when it can't be pushed to.
    public var pushCommand: String?
    /// Review conversations on the diff; `nil` when they couldn't be loaded.
    public var threads: [ReviewThread]?
    /// Whether the brief quotes reviews and open review comments.
    public var includesReviews: Bool

    /// Characters of the description, and of all review text, kept before the rest is cut, so
    /// a huge pull request still leaves the agent room to work.
    static let descriptionBudget = 12_000
    static let reviewBudget = 24_000

    public init(
        pullRequest: PullRequestDetails, branch: String, pushCommand: String?, threads: [ReviewThread]? = [],
        includesReviews: Bool = false
    ) {
        self.pullRequest = pullRequest
        self.branch = branch
        self.pushCommand = pushCommand
        self.threads = threads
        self.includesReviews = includesReviews
    }

    /// The attachment's file name: `pull-request-78.md`.
    public var fileName: String {
        "pull-request-\(pullRequest.number).md"
    }

    public var markdown: String {
        var sections = [header]
        let description = GitHubMarkdown.displayed(pullRequest.body).trimmingCharacters(in: .whitespacesAndNewlines)
        sections.append(
            "## Description\n\n"
                + (description.isEmpty
                    ? "The pull request has no description." : Self.cut(description, to: Self.descriptionBudget)))
        if includesReviews {
            sections.append(reviewSection)
        }
        return sections.joined(separator: "\n\n") + "\n"
    }

    private var header: String {
        let pr = pullRequest
        let repository = pr.baseRepository?.nameWithOwner ?? ""
        let head =
            pr.isCrossRepository ? "\(pr.headRepository?.owner ?? "a deleted fork"):\(pr.headRefName)" : pr.headRefName
        var lines = [
            "# Pull request #\(pr.number): \(pr.title)",
            "",
            pr.url.absoluteString,
            "",
            "- Repository: \(repository)",
        ]
        if let author = pr.author { lines.append("- Author: @\(author)") }
        lines.append("- Merges `\(head)` into `\(pr.baseRefName)`, head commit \(pr.headRefOid.prefix(7))")
        if pr.isDraft { lines.append("- It's a draft.") }
        if pr.state != .open { lines.append("- It's \(pr.state.rawValue.lowercased()).") }
        lines.append("- Checked out in this folder on branch `\(branch)`.")
        if let pushCommand {
            lines.append(
                "- To push to the pull request, run `\(pushCommand)`; a plain `git push` won't, since the branch names differ."
            )
        } else {
            lines.append(
                "- This checkout came from GitHub's read-only copy of the head, so it can't push to the pull request.")
        }
        return lines.joined(separator: "\n")
    }

    private var reviewSection: String {
        var parts: [String] = []
        let reviews = pullRequest.reviews.compactMap { review -> String? in
            let body = GitHubMarkdown.displayed(review.body).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !body.isEmpty else { return nil }
            return "\(Self.verb(for: review)):\n\n\(Self.quoted(body))"
        }
        if !reviews.isEmpty {
            parts.append("### Reviews\n\n" + reviews.joined(separator: "\n\n"))
        }
        let open = threads?.filter { !$0.isResolved && !$0.isPending } ?? []
        if !open.isEmpty {
            let conversations = open.map { thread in
                let place = thread.isFileLevel ? "`\(thread.path)`" : "`\(thread.path)`, \(Self.lines(of: thread))"
                let comments = thread.comments.map { comment in
                    "\(comment.author.map { "@" + $0 } ?? "A reviewer"):\n\(Self.quoted(GitHubMarkdown.displayed(comment.body)))"
                }
                let outdated = thread.isOutdated ? " (outdated: the lines changed since)" : ""
                return "#### \(place)\(outdated)\n\n" + comments.joined(separator: "\n\n")
            }
            parts.append("### Open review comments\n\n" + conversations.joined(separator: "\n\n"))
        }
        if threads == nil {
            parts.append("The review comments on the diff couldn't be loaded; they're on the pull request's page.")
        }
        let body = parts.isEmpty ? "No reviews or open review comments yet." : parts.joined(separator: "\n\n")
        return "## Reviews\n\n" + Self.cut(body, to: Self.reviewBudget)
    }

    private static func verb(for review: Review) -> String {
        let who = review.author.map { "@" + $0 } ?? "A reviewer"
        return switch review.state {
        case .approved: "\(who) approved"
        case .changesRequested: "\(who) requested changes"
        default: "\(who) commented"
        }
    }

    private typealias Review = PullRequestDetails.Review

    private static func lines(of thread: ReviewThread) -> String {
        let end = thread.line ?? thread.originalLine
        guard let end else { return "a line that's gone from the diff" }
        if let start = thread.startLine, start != end { return "lines \(start)-\(end)" }
        return "line \(end)"
    }

    private static func quoted(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { "> " + $0 }
            .joined(separator: "\n")
    }

    private static func cut(_ text: String, to budget: Int) -> String {
        guard text.count > budget else { return text }
        return String(text.prefix(budget)) + "\n\n[Cut here: the rest is on GitHub.]"
    }
}
