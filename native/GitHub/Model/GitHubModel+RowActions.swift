import GitHub
import SwiftUI

/// Merging, closing, reopening and commenting from the pull request list, without opening the
/// page. Merging goes through the page's own model and sheet, so both check the same things: push
/// access, checks and reviews, and the head commit the user saw.
extension GitHubModel {
    /// Opens the merge sheet over the list, loading what GitHub says about the pull request now.
    func requestMerge(_ pullRequest: PullRequestSummary) {
        guard let reference = PullRequestReference(pullRequest) else { return }
        let page = pageModel(for: reference)
        page.actionError = nil
        mergeRequest = reference
        // Always fresh: the sheet merges the head commit it shows.
        Task { await page.load() }
    }

    /// Closes or reopens from the list. Either can be undone from the toast, and the list refreshes.
    func setOpen(_ open: Bool, _ pullRequest: PullRequestSummary) async {
        let url = pullRequest.url
        report(.working(open ? "Reopening…" : "Closing…"), for: url)
        do {
            let cli = await cli()
            if open {
                try await cli.reopen(.number(pullRequest.number), in: location(of: pullRequest))
            } else {
                try await cli.close(.number(pullRequest.number), in: location(of: pullRequest))
            }
        } catch {
            report(.failed("Couldn't \(open ? "reopen" : "close") it: \(error.localizedDescription)"), for: url)
            return
        }
        report(.done(open ? "Reopened" : "Closed"), for: url)
        undo = UndoToastItem(open ? "Reopened \(pullRequest.reference)" : "Closed \(pullRequest.reference)") {
            [weak self] in
            Task { await self?.setOpen(!open, pullRequest) }
        }
        await reloadAfterWrite(pullRequest)
    }

    /// Opens or closes the quick comment box under a row.
    func toggleQuickComment(_ pullRequest: PullRequestSummary) {
        commentingOn = commentingOn == pullRequest.url ? nil : pullRequest.url
        if commentingOn != nil, case .failed? = rowActivity[pullRequest.url] {
            rowActivity[pullRequest.url] = nil
        }
    }

    /// Posts the row's quick comment to the pull request's conversation. A failure keeps the text.
    func postQuickComment(_ pullRequest: PullRequestSummary) async {
        let url = pullRequest.url
        let body = (quickComments[url] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !body.isEmpty, !isPostingComment(pullRequest) else { return }
        report(.working("Posting comment…"), for: url)
        do {
            try await cli().comment(body, on: .number(pullRequest.number), in: location(of: pullRequest))
        } catch {
            report(.failed("Couldn't post the comment: \(error.localizedDescription)"), for: url)
            return
        }
        quickComments[url] = nil
        if commentingOn == url { commentingOn = nil }
        report(.done("Comment posted"), for: url)
        await reloadAfterWrite(pullRequest)
    }

    func isPostingComment(_ pullRequest: PullRequestSummary) -> Bool {
        rowActivity[pullRequest.url] == .working("Posting comment…")
    }

    /// Shows what's happening to a pull request on its row. Success fades after a few seconds; a
    /// failure stays until dismissed or the next action.
    func report(_ activity: PullRequestRowActivity?, for url: URL) {
        rowActivity[url] = activity
        guard case .done = activity else { return }
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(4))
            if self?.rowActivity[url] == activity { self?.rowActivity[url] = nil }
        }
    }

    /// Brings the list, and the page if it's been opened, up to date with a change made from here.
    private func reloadAfterWrite(_ pullRequest: PullRequestSummary) async {
        if let reference = PullRequestReference(pullRequest), let page = pages[reference] {
            Task { await page.load() }
        }
        await refresh()
    }
}
