import GitHub
import SwiftUI

/// Writes to GitHub from the page. Each runs one mutation, then reloads the page, so what's shown
/// is what GitHub has. Where GitHub can take something back, the user gets an undo instead of a
/// confirmation; submitting a review, which it can't, is confirmed in its sheet.
extension PullRequestPageModel {
    /// Starts a comment on a line or range, replacing any unsent one.
    func beginComment(at anchor: ReviewAnchor) {
        draft = ReviewCommentDraft(anchor: anchor, lines: lineText(for: anchor))
    }

    /// Posts the draft: into the pending review, or on its own right away.
    func sendDraft(asReview: Bool) async {
        guard let draft, !draft.body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        let sent = await write("draft") { cli, page in
            if asReview {
                try await cli.addReviewComment(draft.body, at: draft.anchor, on: page)
            } else {
                try await cli.addSingleComment(draft.body, at: draft.anchor, on: page)
            }
        }
        if sent { self.draft = nil }
    }

    func reply(to thread: ReviewThread) async {
        let body = replyDrafts[thread.id, default: ""]
        guard !body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        if await write(thread.id, { cli, page in try await cli.reply(body, to: thread, on: page) }) {
            replyDrafts[thread.id] = nil
        }
    }

    /// Resolving can always be undone, so it happens at once with an undo.
    func setResolved(_ resolved: Bool, _ thread: ReviewThread) async {
        let done = await write(thread.id) { cli, page in try await cli.setResolved(resolved, thread: thread, on: page) }
        guard done else { return }
        undo = UndoToastItem(resolved ? "Conversation resolved" : "Conversation reopened") { [weak self] in
            Task { await self?.setResolved(!resolved, thread) }
        }
    }

    /// Deletes one of the viewer's comments. Undo writes it back at the same lines.
    func delete(_ comment: ReviewComment, in thread: ReviewThread) async {
        let done = await write(comment.id) { cli, page in try await cli.deleteReviewComment(comment, on: page) }
        guard done, let anchor = thread.anchor else { return }
        let isOnlyComment = thread.comments.count == 1
        undo = UndoToastItem("Comment deleted") { [weak self] in
            Task {
                guard let self else { return }
                if isOnlyComment && comment.isPending {
                    _ = await self.write(comment.id) { cli, page in
                        try await cli.addReviewComment(comment.body, at: anchor, on: page)
                    }
                } else {
                    // A reply can only come back as a new reply.
                    self.replyDrafts[thread.id] = comment.body
                    await self.reply(to: thread)
                }
            }
        }
    }

    func update(_ comment: ReviewComment, body: String) async {
        _ = await write(comment.id) { cli, page in try await cli.updateReviewComment(comment, body: body, on: page) }
    }

    func submitReview(_ event: ReviewEvent, body: String) async -> Bool {
        let done = await write("review") { cli, page in try await cli.submitReview(event, body: body, on: page) }
        if done, let gitHub { Task { await gitHub.refresh() } }
        return done
    }

    /// Throws away the pending review and its comments. Confirmed in the sheet first, since GitHub
    /// can't bring them back.
    func discardReview() async {
        guard let reviewID = page?.pendingReview?.id else { return }
        _ = await write("review") { cli, page in try await cli.discardReview(reviewID, on: page) }
    }

    func addConversationComment() async {
        let body = conversationDraft
        guard !body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        if await write("conversation", { cli, page in try await cli.addComment(body, on: page) }) {
            conversationDraft = ""
        }
    }

    func merge(_ method: MergeMethod, deleteBranch: Bool) async -> Bool {
        let done = await write("merge") { cli, page in
            try await cli.merge(page, method: method, deleteBranch: deleteBranch)
        }
        if done, let gitHub { Task { await gitHub.refresh() } }
        return done
    }

    // MARK: - Agents

    var canAskAgent: Bool {
        gitHub?.askAgent != nil
    }

    var canSendToCurrentTask: Bool {
        gitHub?.hasCurrentTask() ?? false
    }

    func askAgent(
        about anchor: ReviewAnchor, thread: ReviewThread? = nil, request: String? = nil,
        destination: GitHubAgentDestination
    ) async {
        guard let page, let askAgent = gitHub?.askAgent else { return }
        let prompt = ReviewAgentPrompt(
            reference: reference, title: page.title, branch: page.headRefName, anchor: anchor,
            excerpt: excerpt(for: anchor),
            notes: (thread?.comments ?? []).map { ReviewAgentPrompt.Note(author: $0.author, body: $0.body) },
            request: request)
        busy.insert("agent")
        defer { busy.remove("agent") }
        do {
            try await askAgent(prompt, destination)
        } catch let error as GitHubError {
            actionError = error
        } catch {
            actionError = .failed(exitCode: 0, error.localizedDescription)
        }
    }

    // MARK: - Running writes

    /// Runs a write against the loaded page, marking `key` busy, then reloads. Returns whether it
    /// worked; a failure lands in `actionError`, said in GitHub's words.
    func write(_ key: String, _ body: (GitHubCLI, PullRequestPage) async throws -> Void) async -> Bool {
        guard let gitHub, let page, !busy.contains(key) else { return false }
        busy.insert(key)
        defer { busy.remove(key) }
        do {
            try await body(gitHub.cli(), page)
        } catch let error as GitHubError {
            actionError = error
            return false
        } catch {
            actionError = .failed(exitCode: 0, error.localizedDescription)
            return false
        }
        await load()
        return true
    }
}
