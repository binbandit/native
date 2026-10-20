import GitHub
import SwiftUI

/// A task's pull request at a glance, in its sidebar badge's hover card: number and state, title,
/// repository and head → base, then its checks, review and whether it can merge (a merge queue or
/// auto-merge included), and what to do with it. It shows what the branch lookup found at once and
/// refreshes that, then loads the pull request's page for how it merges and whether the user may,
/// the rules the page's merge sheet follows.
struct TaskPullRequestCard: View {
    let branch: BranchReference
    /// Closes the card before an action takes the user elsewhere.
    let dismiss: @MainActor () -> Void

    @Environment(GitHubModel.self) private var model
    @State private var didCopy = false

    /// A lookup younger than this is fresh enough for a glance.
    private static let freshness: TimeInterval = 30

    var body: some View {
        if let found = model.branchPullRequest(for: branch), let pullRequest = found.pullRequest {
            let page = PullRequestReference(pullRequest).map(model.pageModel(for:))
            let facts = TaskPullRequestFacts(pullRequest: pullRequest, page: page?.page)
            PopoverPanel(title: "Pull Request #\(pullRequest.number)", width: DS.Size.hoverCardWidth) {
                stateLabel(facts)
            } content: {
                VStack(alignment: .leading, spacing: DS.Space.lg) {
                    heading(found, facts)
                    notice(found, page: page)
                        // A popover sizes to its content's ideal height; this lets the notice wrap.
                        .fixedSize(horizontal: false, vertical: true)
                    status(facts, page: page)
                }
                .padding(DS.Space.lg)
                SeparatorLine()
                actions(facts, page: page?.page)
            }
            .task(id: pullRequest.url) { await refresh(page, isOpen: facts.isOpen, maxAge: Self.freshness) }
        }
    }

    // MARK: - Parts

    private func stateLabel(_ facts: TaskPullRequestFacts) -> some View {
        let icon = PullRequestStateIcon(
            state: facts.state, isDraft: facts.isDraft, size: DS.Size.navIcon, hasTooltip: false)
        return HStack(spacing: DS.Space.xs) {
            icon
            Text(icon.label)
                .font(.dsCaptionMedium)
                .foregroundStyle(facts.isDraft && facts.isOpen ? .dsTextSecondary : icon.tint)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(icon.label)
    }

    private func heading(_ found: BranchPullRequest, _ facts: TaskPullRequestFacts) -> some View {
        VStack(alignment: .leading, spacing: DS.Space.sm) {
            DSInlineCodeText(facts.title)
                .font(.dsBodyMedium)
                .foregroundStyle(.dsTextPrimary)
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: DS.Space.xs) {
                Text(facts.pullRequest.repository)
                if !found.others.isEmpty {
                    Text(verbatim: "·")
                    Text(othersLabel(found))
                        .help(found.others.map(othersLine).joined(separator: "\n"))
                }
            }
            .font(.dsCaption)
            .foregroundStyle(.dsTextTertiary)
            .lineLimit(1)
            if let head = facts.head, let base = facts.base {
                // The base is short (main) and says where it lands; the head truncates first.
                HStack(spacing: DS.Space.xs) {
                    BranchChip(name: head)
                    Image(systemName: "arrow.right")
                        .font(.system(size: DS.Size.navIcon - DS.Space.xxs))
                        .foregroundStyle(.dsTextTertiary)
                        .accessibilityLabel("into")
                    BranchChip(name: base)
                        .layoutPriority(1)
                }
            }
        }
    }

    /// Why what's shown may be old, and the one thing that fixes it.
    @ViewBuilder private func notice(_ found: BranchPullRequest, page: PullRequestPageModel?) -> some View {
        if model.availability == .notAuthenticated || model.availability == .notInstalled {
            let isInstalled = model.availability == .notAuthenticated
            NoticeBanner(
                tone: .warning, systemImage: isInstalled ? "person.badge.key" : "terminal",
                title: isInstalled ? "GitHub CLI isn't signed in" : "GitHub CLI isn't installed",
                detail: isInstalled
                    ? "This may be out of date. Run gh auth login in a terminal, then check again."
                    : "This may be out of date. Install it with brew install gh, then check again."
            ) {
                Button(model.isRefreshing ? "Checking…" : "Check Again") {
                    Task {
                        await model.refresh(rereadEnvironment: true)
                        await refresh(page, isOpen: found.pullRequest?.state == .open, maxAge: 0)
                    }
                }
                .buttonStyle(.ds(.secondary))
                .disabled(model.isRefreshing)
            }
        } else if let failure = found.failure {
            NoticeBanner(
                tone: .warning, systemImage: Self.isOffline(failure) ? "wifi.slash" : "exclamationmark.triangle",
                title: Self.isOffline(failure) ? "GitHub can't be reached" : "This couldn't refresh",
                detail: "Showing what GitHub said at \(DSFormat.time(found.loadedAt, now: .now))."
            ) {
                Button("Retry") {
                    Task { await refresh(page, isOpen: found.pullRequest?.state == .open, maxAge: 0) }
                }
                .buttonStyle(.ds(.secondary))
            }
        }
    }

    @ViewBuilder private func status(_ facts: TaskPullRequestFacts, page: PullRequestPageModel?) -> some View {
        switch facts.state {
        case .merged:
            Text("Merged into \(facts.base ?? "its base"). Open it for the conversation and changes.")
                .font(.dsBody)
                .foregroundStyle(.dsTextSecondary)
                .fixedSize(horizontal: false, vertical: true)
        case .closed:
            Text("Closed without merging. Reopen it on GitHub to pick it back up.")
                .font(.dsBody)
                .foregroundStyle(.dsTextSecondary)
                .fixedSize(horizontal: false, vertical: true)
        case .open, .other:
            VStack(alignment: .leading, spacing: DS.Space.sm) {
                Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: DS.Space.lg, verticalSpacing: DS.Space.sm)
                {
                    // The values take the rest of the card's width, so they wrap only when they must.
                    GridRow {
                        rowLabel("Checks")
                        checks(facts)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    GridRow {
                        rowLabel("Review")
                        value(Self.review(facts))
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    GridRow {
                        rowLabel("Merge")
                        merge(facts, page: page)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                // Merging needs push access; saying so explains the missing Merge button.
                if let loaded = page?.page, loaded.isOpen, !loaded.isDraft, !loaded.viewerCanMerge,
                    let blocker = PullRequestMergePlan(page: loaded).blocker
                {
                    Text(blocker)
                        .font(.dsCaption)
                        .foregroundStyle(.dsTextTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    @ViewBuilder private func checks(_ facts: TaskPullRequestFacts) -> some View {
        if let checks = facts.checks {
            Button {
                dismiss()
                Task { await model.openChecks(facts.pullRequest) }
            } label: {
                HStack(spacing: DS.Space.xs) {
                    ChecksIndicator(checks: checks, hasTooltip: false)
                    Text(ChecksIndicator.summary(checks).replacingOccurrences(of: "Checks: ", with: ""))
                        .foregroundStyle(.dsTextSecondary)
                    Image(systemName: "arrow.up.right")
                        .font(.system(size: DS.Size.navIcon - DS.Space.xxs))
                        .foregroundStyle(.dsTextTertiary)
                }
                .font(.dsBody)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .help(checks.state == .failing ? "Open the failing check on GitHub" : "Open its checks on GitHub")
        } else {
            value(("None reported", .dsTextTertiary))
        }
    }

    @ViewBuilder private func merge(_ facts: TaskPullRequestFacts, page: PullRequestPageModel?) -> some View {
        if facts.isDraft {
            value(("Mark it ready for review on GitHub to merge", .dsTextTertiary))
        } else if let loaded = page?.page {
            value(loaded.mergeVerdict ?? ("GitHub is still working it out", .dsTextTertiary))
        } else if hasNotice(model.branchPullRequest(for: branch)) {
            value(("Unknown until GitHub answers", .dsTextTertiary))
        } else if let page, let error = page.loadError, !page.isLoading {
            HStack(spacing: DS.Space.sm) {
                value(("Couldn't check", .dsWarning))
                    .help(error.localizedDescription)
                Button("Retry") {
                    Task { await page.load(prefetchingPatches: false) }
                }
                .buttonStyle(.ds(.ghost))
            }
        } else {
            HStack(spacing: DS.Space.xs) {
                DotGridLoader(pattern: .waiting)
                    .foregroundStyle(.dsTextSecondary)
                    .frame(width: DS.Size.navIcon, height: DS.Size.navIcon)
                value(("Checking…", .dsTextSecondary))
            }
        }
    }

    private func actions(_ facts: TaskPullRequestFacts, page: PullRequestPage?) -> some View {
        let pullRequest = facts.pullRequest
        return HStack(spacing: DS.Space.sm) {
            Button("Open in Native") {
                dismiss()
                model.openInNative(pullRequest)
            }
            .buttonStyle(.ds(.primary))
            // The page's merge sheet, with its checks and confirmation; only for someone who may
            // merge, once the page has said so.
            if page != nil, model.offersMerge(pullRequest) {
                Button("Merge…") {
                    dismiss()
                    model.requestMerge(pullRequest)
                }
                .buttonStyle(.ds(.secondary))
            }
            Spacer(minLength: 0)
            IconButton("Open on GitHub", systemImage: "arrow.up.right") {
                dismiss()
                model.openInBrowser(pullRequest)
            }
            IconButton(didCopy ? "Copied" : "Copy Link", systemImage: didCopy ? "checkmark" : "link") {
                model.copyURL(pullRequest)
                didCopy = true
            }
            .task(id: didCopy) {
                guard didCopy else { return }
                try? await Task.sleep(for: .seconds(1.5))
                didCopy = false
            }
        }
        .padding(.leading, DS.Space.lg)
        .padding(.trailing, DS.Space.sm)
        .padding(.vertical, DS.Space.md)
    }

    private func rowLabel(_ title: String) -> some View {
        Text(title)
            .font(.dsBody)
            .foregroundStyle(.dsTextTertiary)
            .gridColumnAlignment(.leading)
    }

    private func value(_ text: (label: String, tint: Color)) -> some View {
        Text(text.label)
            .font(.dsBody)
            .foregroundStyle(text.tint)
            .fixedSize(horizontal: false, vertical: true)
    }

    // MARK: - Loading

    /// Refreshes the branch's lookup and, for an open pull request, its page (without the diffs a
    /// glance doesn't need).
    private func refresh(_ page: PullRequestPageModel?, isOpen: Bool, maxAge: TimeInterval) async {
        async let lookup: Void = model.loadPullRequest(for: branch, maxAge: maxAge)
        if isOpen, let page, model.availability != .notAuthenticated,
            maxAge == 0 || page.page == nil || page.isStale
        {
            await page.load(prefetchingPatches: false)
        }
        await lookup
    }

    private func hasNotice(_ found: BranchPullRequest?) -> Bool {
        model.availability == .notAuthenticated || model.availability == .notInstalled || found?.failure != nil
    }

    // MARK: - Wording

    private func othersLabel(_ found: BranchPullRequest) -> String {
        let count = found.others.count
        return found.othersAreEarlier ? "and \(count) earlier" : "and \(count) other\(count == 1 ? "" : "s")"
    }

    /// "#12 · Merged · Fix the thing", for the others' tooltip.
    private func othersLine(_ pullRequest: PullRequestSummary) -> String {
        let state = PullRequestStateIcon(state: pullRequest.state, isDraft: pullRequest.isDraft).label
        return "#\(pullRequest.number) · \(state) · \(pullRequest.title)"
    }

    private static func review(_ facts: TaskPullRequestFacts) -> (label: String, tint: Color) {
        if facts.isDraft { return ("Draft", .dsTextTertiary) }
        return switch facts.reviewDecision {
        case .approved: ("Approved", .dsSuccess)
        case .changesRequested: ("Changes requested", .dsDanger)
        case .reviewRequired: ("Waiting for a review", .dsTextSecondary)
        case .other, nil: ("Not required", .dsTextTertiary)
        }
    }

    private static func isOffline(_ error: GitHubError) -> Bool {
        switch error {
        case .offline, .timedOut: true
        default: false
        }
    }
}

/// What the card says about the pull request: the page's answer once it's loaded (fresher, and the
/// only one with merge rules), else the branch lookup's.
private struct TaskPullRequestFacts {
    let pullRequest: PullRequestSummary
    let page: PullRequestPage?

    var state: PullRequest.State { page?.state ?? pullRequest.state }
    var isDraft: Bool { page?.isDraft ?? pullRequest.isDraft }
    var isOpen: Bool { state == .open }
    var title: String { page?.title ?? pullRequest.title }
    var checks: CheckSummary? { page.map(\.checks) ?? pullRequest.checks }
    var reviewDecision: PullRequest.ReviewDecision? { page.map(\.reviewDecision) ?? pullRequest.reviewDecision }
    var head: String? { page?.headRefName ?? pullRequest.headRefName }
    var base: String? { page?.baseRefName ?? pullRequest.baseRefName }
}
