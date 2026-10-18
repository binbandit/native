import Foundation

/// What an agent gets when the user asks it about lines of a pull request: which pull request and
/// branch, the lines as diff, the review comments on them, and what to do. Agents work in a
/// checkout of the branch, so the prompt names files by their path in the repository.
public struct ReviewAgentPrompt: Sendable, Hashable {
    public struct Note: Sendable, Hashable {
        public var author: String?
        public var body: String

        public init(author: String?, body: String) {
            self.author = author
            self.body = body
        }
    }

    public var reference: PullRequestReference
    public var title: String
    public var branch: String
    public var anchor: ReviewAnchor
    /// The lines as unified diff, `+`/`-`/space prefixed.
    public var excerpt: String
    public var notes: [Note]
    /// What the user asked, if they wrote something.
    public var request: String?

    public init(
        reference: PullRequestReference, title: String, branch: String, anchor: ReviewAnchor,
        excerpt: String,
        notes: [Note] = [], request: String? = nil
    ) {
        self.reference = reference
        self.title = title
        self.branch = branch
        self.anchor = anchor
        self.excerpt = excerpt
        self.notes = notes
        self.request = request
    }

    /// The instruction when the user didn't write one.
    public var defaultRequest: String {
        notes.isEmpty
            ? "Review these lines: look for bugs, unclear code and missing tests, and fix what you find."
            : "Address the review feedback above: change the code on this branch, or explain why it should stay as it is."
    }

    public var text: String {
        var sections = [
            "This is about pull request \(reference.display) (\u{201C}\(title)\u{201D}), branch `\(branch)`: \(reference.url.absoluteString)",
            "`\(anchor.path)`, \(anchor.lineDescription) on the \(anchor.side == .left ? "base" : "head") side:\n\n```diff\n\(excerpt)\n```",
        ]
        if !notes.isEmpty {
            let quoted = notes.map { note in
                let body = note.body.trimmingCharacters(in: .whitespacesAndNewlines)
                    .split(separator: "\n", omittingEmptySubsequences: false)
                    .map { "> " + $0 }
                    .joined(separator: "\n")
                return "\(note.author.map { "@" + $0 } ?? "A reviewer") wrote:\n\(body)"
            }
            sections.append("Review comments on these lines:\n\n" + quoted.joined(separator: "\n\n"))
        }
        let request = request?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        sections.append(request.isEmpty ? defaultRequest : request)
        return sections.joined(separator: "\n\n")
    }
}
