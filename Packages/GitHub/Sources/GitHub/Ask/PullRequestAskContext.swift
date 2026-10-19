import Foundation

/// The context a private question about a pull request goes out with, cut to a budget, and the
/// files saved beside the agent with everything that didn't fit.
///
/// The context is sent once, with the first question, and stays in the conversation (and the
/// provider's prompt cache) for the follow-ups, so a small pull request costs one turn and no tool
/// calls. A large one sends its outline instead: every file by name with its size, the
/// conversation and review threads that fit, and as many file diffs as fit, preferring files that
/// reviewers commented on and skipping generated ones. The agent reads the rest from the saved
/// copy (`PULL_REQUEST.md`, `changes.diff`, `diff/<path>.diff`) only when a question needs it.
public struct PullRequestAskContext: Sendable, Hashable {
    /// Limits in characters, about four to a token.
    public struct Budget: Sendable, Hashable {
        public var total: Int
        public var description: Int
        /// One conversation comment.
        public var comment: Int
        public var conversation: Int
        /// One comment in a review thread.
        public var threadNote: Int
        public var threads: Int
        /// Files named in the list before it says how many more there are.
        public var listedFiles: Int
        /// The largest file diff sent when the whole diff doesn't fit.
        public var filePatch: Int

        public init(
            total: Int, description: Int, comment: Int, conversation: Int, threadNote: Int, threads: Int,
            listedFiles: Int, filePatch: Int
        ) {
            self.total = total
            self.description = description
            self.comment = comment
            self.conversation = conversation
            self.threadNote = threadNote
            self.threads = threads
            self.listedFiles = listedFiles
            self.filePatch = filePatch
        }

        /// About 20k tokens: a typical pull request goes whole, and a follow-up costs little once cached.
        public static let standard = Budget(
            total: 80_000, description: 8_000, comment: 3_000, conversation: 16_000, threadNote: 1_500,
            threads: 16_000, listedFiles: 300, filePatch: 16_000)
    }

    /// The context, for the opening prompt.
    public var text: String
    public var inclusion: PullRequestAskInclusion
    /// Files for the agent's folder, by path inside it.
    public var workspace: [PullRequestAskWorkspaceFile]

    public init(_ source: PullRequestAskSource, budget: Budget = .standard) {
        var inclusion = PullRequestAskInclusion()
        let body = source.body.trimmingCharacters(in: .whitespacesAndNewlines)
        inclusion.hasDescription = !body.isEmpty
        inclusion.descriptionTrimmed = body.count > budget.description
        inclusion.commentsLoaded = source.comments.count
        inclusion.conversationContinues = source.hasMoreConversation
        inclusion.threadsLoaded = source.threads.count
        inclusion.threadsTotal = max(source.threadsTotal, source.threads.count)
        inclusion.files = max(source.filesTotal, source.files.count)
        inclusion.filesListed = source.files.count
        inclusion.filesWithPatch = source.files.count { $0.patch != nil }
        inclusion.filesWithoutPatch = source.files.count { if case .missing = $0.diff { true } else { false } }
        inclusion.additions = source.additions
        inclusion.deletions = source.deletions

        var sections = [Self.header(source)]
        sections.append(
            "## Description\n\n" + (body.isEmpty ? "No description provided." : Self.trim(body, to: budget.description))
        )

        let comments = Self.latest(source.comments, within: budget.conversation) {
            Self.render($0, limit: budget.comment)
        }
        inclusion.comments = comments.count
        if !source.comments.isEmpty || source.hasMoreConversation {
            sections.append(Self.conversationSection(comments, of: source, limit: budget.comment))
        }

        let threads = Self.prefix(Self.threadOrder(source.threads), within: budget.threads) {
            Self.render($0, noteLimit: budget.threadNote, withHunk: false)
        }
        inclusion.threads = threads.count
        if !source.threads.isEmpty {
            sections.append(Self.threadsSection(threads, of: source, noteLimit: budget.threadNote))
        }

        sections.append(Self.fileList(source, limit: budget.listedFiles))

        // The diff gets what's left: whole if it fits, otherwise the files most worth reading.
        let used = sections.reduce(0) { $0 + $1.count + 2 }
        let room = max(budget.total - used, 0)
        let patched = source.files.filter { $0.patch != nil }
        let whole = patched.reduce(0) { $0 + Self.diff(of: $1).count + 1 }
        let inline: [PullRequestAskSource.File]
        if whole <= room {
            inline = patched
        } else {
            let candidates = Self.diffOrder(patched, threads: source.threads).filter {
                !$0.isGenerated && Self.diff(of: $0).count <= budget.filePatch
            }
            inline = Self.prefix(candidates, within: room) { Self.diff(of: $0) }
        }
        inclusion.filesInDiff = inline.count
        if !patched.isEmpty {
            sections.append(Self.diffSection(inline, isWhole: inline.count == patched.count))
        }

        text = sections.joined(separator: "\n\n")
        self.inclusion = inclusion
        workspace = Self.workspace(source)
    }

    // MARK: - Sections

    static func header(_ source: PullRequestAskSource) -> String {
        var lines = [
            "# \(source.reference.display): \(source.title)",
            source.reference.url.absoluteString,
            "",
            "- State: \(stateText(source))",
        ]
        if let author = source.author { lines.append("- Author: @\(author)") }
        lines.append(
            "- Branch: `\(source.headRefName)` into `\(source.baseRefName)`, head commit `\(source.headRefOid.prefix(12))`"
        )
        lines.append(
            "- Size: \(PullRequestAskInclusion.counted(source.filesTotal, "file")) changed, +\(source.additions) -\(source.deletions)"
        )
        if !source.labels.isEmpty { lines.append("- Labels: " + source.labels.joined(separator: ", ")) }
        if let decision = source.reviewDecision.flatMap(decisionText) { lines.append("- Review decision: \(decision)") }
        if let checks = source.checks { lines.append("- Checks: \(checksText(checks))") }
        return lines.joined(separator: "\n")
    }

    private static func stateText(_ source: PullRequestAskSource) -> String {
        let state =
            switch source.state {
            case .open: "open"
            case .closed: "closed without merging"
            case .merged: "merged"
            case .other: "unknown"
            }
        return source.isDraft ? state + ", draft" : state
    }

    private static func decisionText(_ decision: PullRequest.ReviewDecision) -> String? {
        switch decision {
        case .approved: "approved"
        case .changesRequested: "changes requested"
        case .reviewRequired: "review required"
        case .other: nil
        }
    }

    private static func checksText(_ checks: CheckSummary) -> String {
        let counts = [
            checks.failed > 0 ? "\(checks.failed) failing" : nil,
            checks.pending > 0 ? "\(checks.pending) pending" : nil,
            checks.passed > 0 ? "\(checks.passed) passing" : nil,
            checks.skipped > 0 ? "\(checks.skipped) skipped" : nil,
        ].compactMap(\.self)
        return checks.state.rawValue + (counts.isEmpty ? "" : " (" + counts.joined(separator: ", ") + ")")
    }

    private static func conversationSection(
        _ comments: [PullRequestAskSource.Comment], of source: PullRequestAskSource, limit: Int?
    ) -> String {
        var parts = ["## Conversation"]
        let skipped = source.comments.count - comments.count
        if skipped > 0 {
            parts.append("(\(PullRequestAskInclusion.counted(skipped, "earlier comment")) are in PULL_REQUEST.md.)")
        }
        parts += comments.map { render($0, limit: limit) }
        if source.hasMoreConversation {
            parts.append("(The conversation goes on past what Native loaded; read the rest on GitHub with gh.)")
        }
        if comments.isEmpty, skipped == 0, !source.hasMoreConversation { parts.append("No comments yet.") }
        return parts.joined(separator: "\n\n")
    }

    private static func threadsSection(
        _ threads: [PullRequestAskSource.Thread], of source: PullRequestAskSource, noteLimit: Int?,
        withHunk: Bool = false
    ) -> String {
        let open = source.threads.count { !$0.isResolved }
        var parts = ["## Review threads (\(source.threads.count), \(open) unresolved)"]
        parts += threads.map { render($0, noteLimit: noteLimit, withHunk: withHunk) }
        let skipped = source.threads.count - threads.count
        if skipped > 0 {
            parts.append(
                "(\(PullRequestAskInclusion.counted(skipped, "more thread")) didn't fit here; they're in PULL_REQUEST.md.)"
            )
        }
        return parts.joined(separator: "\n\n")
    }

    static func render(_ comment: PullRequestAskSource.Comment, limit: Int?) -> String {
        let who = comment.author.map { "@" + $0 } ?? "Someone"
        let verb =
            switch comment.kind {
            case .comment: "commented"
            case .review(.approved): "approved"
            case .review(.changesRequested): "requested changes"
            case .review(.dismissed): "reviewed (dismissed)"
            case .review: "reviewed"
            }
        let date = comment.date.map { " on " + day($0) } ?? ""
        let body = comment.body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !body.isEmpty else { return "\(who) \(verb)\(date)." }
        return "\(who) \(verb)\(date):\n" + quote(limit.map { trim(body, to: $0) } ?? body)
    }

    static func render(_ thread: PullRequestAskSource.Thread, noteLimit: Int?, withHunk: Bool) -> String {
        let place = thread.line.map { "\(thread.path):\($0)" } ?? thread.path
        let flags = [thread.isResolved ? "resolved" : "unresolved", thread.isOutdated ? "outdated" : nil]
            .compactMap(\.self).joined(separator: ", ")
        var parts = ["### `\(place)` (\(flags))"]
        if withHunk, !thread.diffHunk.isEmpty {
            parts.append(fenced(thread.diffHunk, language: "diff"))
        }
        parts += thread.notes.map { note in
            let body = note.body.trimmingCharacters(in: .whitespacesAndNewlines)
            return (note.author.map { "@" + $0 } ?? "Someone") + ":\n"
                + quote(noteLimit.map { trim(body, to: $0) } ?? body)
        }
        return parts.joined(separator: "\n\n")
    }

    static func fileList(_ source: PullRequestAskSource, limit: Int?) -> String {
        var lines = ["## Changed files (\(source.filesTotal))", ""]
        let shown = limit.map { Array(source.files.prefix($0)) } ?? source.files
        lines += shown.map(fileLine)
        let unlisted = source.filesTotal - shown.count
        if unlisted > 0 {
            lines.append(
                shown.count < source.files.count
                    ? "- …and \(unlisted.formatted()) more, listed in PULL_REQUEST.md"
                    : "- …and \(unlisted.formatted()) more that Native didn't load")
        }
        return lines.joined(separator: "\n")
    }

    private static func fileLine(_ file: PullRequestAskSource.File) -> String {
        let kind =
            switch file.changeType {
            case .added: "added"
            case .deleted: "deleted"
            case .renamed: "renamed" + (file.previousPath.map { " from `\($0)`" } ?? "")
            case .copied: "copied" + (file.previousPath.map { " from `\($0)`" } ?? "")
            case .modified, .changed, .other: "modified"
            }
        var notes = ["\(kind), +\(file.additions) -\(file.deletions)"]
        if file.isGenerated { notes.append("generated") }
        switch file.diff {
        case .patch: break
        case .missing(.binary): notes.append("binary, no diff")
        case .missing(.tooLarge): notes.append("GitHub doesn't show its diff (too large)")
        case .missing(.renamedOnly): notes.append("only renamed")
        case .notLoaded: notes.append("diff not loaded")
        }
        return "- `\(file.path)` (" + notes.joined(separator: "; ") + ")"
    }

    private static func diffSection(_ files: [PullRequestAskSource.File], isWhole: Bool) -> String {
        let title =
            isWhole
            ? "## Diff"
            : "## Diff (\(files.count) of the files; the rest are in `diff/` and `changes.diff`)"
        guard !files.isEmpty else { return title + "\n\nNo file diff fit here; read them from `diff/`." }
        return title + "\n\n" + fenced(files.map(diff).joined(separator: "\n"), language: "diff")
    }

    /// A file's diff as git prints it, headers first, from GitHub's hunks.
    static func diff(of file: PullRequestAskSource.File) -> String {
        let old = file.previousPath ?? file.path
        let from = file.changeType == .added ? "/dev/null" : "a/" + old
        let to = file.changeType == .deleted ? "/dev/null" : "b/" + file.path
        let patch = file.patch ?? ""
        return "diff --git a/\(old) b/\(file.path)\n--- \(from)\n+++ \(to)\n" + patch
            + (patch.hasSuffix("\n") ? "" : "\n")
    }

    // MARK: - Choosing what fits

    /// The newest items whose rendering fits `budget` together, back in their order.
    static func latest<Item>(_ items: [Item], within budget: Int, size: (Item) -> String) -> [Item] {
        Array(prefix(items.reversed(), within: budget, size: size).reversed())
    }

    /// The leading items whose rendering fits `budget` together.
    static func prefix<Item>(_ items: some Sequence<Item>, within budget: Int, size: (Item) -> String) -> [Item] {
        var used = 0
        var kept: [Item] = []
        for item in items {
            let cost = size(item).count + 2
            guard used + cost <= budget else { break }
            used += cost
            kept.append(item)
        }
        return kept
    }

    /// Unresolved threads first, since they're what's still being discussed; otherwise as listed.
    static func threadOrder(_ threads: [PullRequestAskSource.Thread]) -> [PullRequestAskSource.Thread] {
        threads.filter { !$0.isResolved } + threads.filter(\.isResolved)
    }

    /// Files reviewers are discussing first, then the rest as GitHub lists them.
    static func diffOrder(
        _ files: [PullRequestAskSource.File], threads: [PullRequestAskSource.Thread]
    ) -> [PullRequestAskSource.File] {
        let discussed = Set(threads.filter { !$0.isResolved }.map(\.path))
        return files.filter { discussed.contains($0.path) } + files.filter { !discussed.contains($0.path) }
    }

    // MARK: - The saved copy

    static func workspace(_ source: PullRequestAskSource) -> [PullRequestAskWorkspaceFile] {
        var sections = [header(source)]
        let body = source.body.trimmingCharacters(in: .whitespacesAndNewlines)
        sections.append("## Description\n\n" + (body.isEmpty ? "No description provided." : body))
        if !source.comments.isEmpty || source.hasMoreConversation {
            sections.append(conversationSection(source.comments, of: source, limit: nil))
        }
        if !source.threads.isEmpty {
            sections.append(threadsSection(source.threads, of: source, noteLimit: nil, withHunk: true))
        }
        sections.append(fileList(source, limit: nil))
        var files = [
            PullRequestAskWorkspaceFile(path: "PULL_REQUEST.md", contents: sections.joined(separator: "\n\n") + "\n")
        ]
        let patched = source.files.filter { $0.patch != nil }
        if !patched.isEmpty {
            files.append(PullRequestAskWorkspaceFile(path: "changes.diff", contents: patched.map(diff).joined()))
        }
        for file in patched {
            guard let path = PullRequestAskWorkspaceFile.safePath(file.path) else { continue }
            files.append(PullRequestAskWorkspaceFile(path: "diff/\(path).diff", contents: diff(of: file)))
        }
        return files
    }

    // MARK: - Text

    /// Cuts at a line break where possible, marking what was left out.
    static func trim(_ text: String, to limit: Int) -> String {
        PullRequestDraftPrompt.trim(text, to: limit)
    }

    static func quote(_ text: String) -> String {
        text.split(separator: "\n", omittingEmptySubsequences: false).map { $0.isEmpty ? ">" : "> " + $0 }
            .joined(separator: "\n")
    }

    /// A code fence longer than any run of backticks inside, so the content can't close it.
    static func fenced(_ text: String, language: String) -> String {
        var longest = 0
        var run = 0
        for character in text {
            run = character == "`" ? run + 1 : 0
            longest = max(longest, run)
        }
        let fence = String(repeating: "`", count: max(3, longest + 1))
        return fence + language + "\n" + text + (text.hasSuffix("\n") ? "" : "\n") + fence
    }

    private static func day(_ date: Date) -> String {
        date.formatted(.iso8601.year().month().day())
    }
}
