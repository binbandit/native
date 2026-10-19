import CodeThemes
import GitHub
import Observation
import SwiftUI

/// One pull request's page: what GitHub says about it, loaded in one query and kept fresh, plus
/// what the user is doing on it (the tab, drafts, collapsed files). Writes live in the
/// `+Review` extension and files in `+Files`.
@Observable
final class PullRequestPageModel {
    enum Tab: String, CaseIterable, Identifiable {
        case conversation, files, checks

        var id: Self { self }

        /// The tab a GitHub link points at: `/pull/1/files`, `/pull/1/checks`.
        init?(url: URL) {
            let parts = url.pathComponents
            guard let pull = parts.firstIndex(of: "pull"), parts.count > pull + 2 else { return nil }
            switch parts[pull + 2] {
            case "files": self = .files
            case "checks": self = .checks
            default: return nil
            }
        }

        var title: String {
            switch self {
            case .conversation: "Conversation"
            case .files: "Files Changed"
            case .checks: "Checks"
            }
        }
    }

    let reference: PullRequestReference
    @ObservationIgnored weak var gitHub: GitHubModel?

    private(set) var page: PullRequestPage?
    /// Why the last load failed. With a page already shown, the page stays and this explains why
    /// it may be out of date.
    private(set) var loadError: GitHubError?
    private(set) var isLoading = false
    private(set) var loadedAt: Date?
    private(set) var isLoadingMoreTimeline = false
    var tab: Tab = .conversation

    // Files: GraphQL lists them all with the viewed marks; REST brings patches a hundred at a time.
    var files: [ChangedFile] = []
    var filesCursor: String?
    var patches: [String: FilePatch] = [:]
    /// Each patch parsed once, as it arrives, rather than on every redraw.
    var hunks: [String: [DiffHunk]] = [:]
    /// Each hunk's lines highlighted (`hunkKey`), filled in off the main thread as files show.
    var highlighted: [String: [[CodeSegment]]] = [:]
    @ObservationIgnored var highlightedPaths: Set<String> = []
    /// Measured once as patches arrive, since every file's header asks.
    @ObservationIgnored var lineCounts: [String: Int] = [:]
    @ObservationIgnored var largeDiffs: Set<String> = []
    /// Cut-off lines the user opened (`lineKey`).
    var expandedLines: Set<String> = []
    /// Files whose long lines wrap, by repository and path; remembered across launches.
    var wrappedFiles: Set<String> = PullRequestPageModel.storedWrappedFiles()
    /// Large diffs the user asked to see; the rest wait behind "Load Diff", as on GitHub.
    var loadedLargeDiffs: Set<String> = []
    /// Built diff text by block, so scrolling past a hunk again doesn't rebuild it.
    @ObservationIgnored var blockTexts: [String: PullRequestDiffBlockText] = [:]
    var patchPagesLoaded = 0
    var patchesComplete = false
    var isLoadingPatches = false
    var patchError: GitHubError?
    /// Files the user opened or closed, overriding the default (viewed and generated files closed).
    var collapseOverrides: [String: Bool] = [:]
    /// The file the tree asked to scroll to.
    var focusedFile: String?

    private(set) var checks: [PullRequestCheck]?
    private(set) var checksError: GitHubError?
    private(set) var isLoadingChecks = false

    /// The new line comment being written, if any.
    var draft: ReviewCommentDraft?
    /// Lines being picked for a new comment by dragging in the gutter, highlighted as they're picked.
    var lineSelection: ReviewLineSelection?
    /// The conversation under the pointer or being replied to, whose lines are highlighted.
    var highlightedThread: ReviewThread.ID?
    /// Conversations folded or opened by hand; the rest follow whether they're resolved.
    var threadExpansion: [ReviewThread.ID: Bool] = [:]
    /// Where each block of diff lines sits in the Files Changed list, by hunk then first line, so a
    /// drag in the gutter can cross from one block to the next.
    @ObservationIgnored var blockOrigins: [String: [Int: (end: Int, minY: CGFloat)]] = [:]
    var replyDrafts: [String: String] = [:]
    var conversationDraft = ""
    /// Bumped to scroll to the conversation's comment box and focus it.
    var composerFocusRequest = 0
    /// Writes under way, by what they're about, so the right control shows progress.
    var busy: Set<String> = []
    var actionError: GitHubError?
    var undo: UndoToastItem?
    var isReviewSheetPresented = false
    var isMergeSheetPresented = false

    init(reference: PullRequestReference, gitHub: GitHubModel) {
        self.reference = reference
        self.gitHub = gitHub
    }

    /// Pages refresh when shown if they're older than this; writes refresh at once.
    static let freshness: TimeInterval = 60

    var isStale: Bool {
        loadedAt.map { Date.now.timeIntervalSince($0) > Self.freshness } ?? true
    }

    // MARK: - Loading

    func loadIfStale() async {
        if isStale { await load() }
    }

    /// Loads the page in one query, keeping what's shown on failure.
    func load() async {
        guard !isLoading, let gitHub else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            let page = try await gitHub.cli().pullRequestPage(reference)
            apply(page)
            loadError = nil
            // The first hundred diffs load now, so Files Changed opens with them ready.
            if patchPagesLoaded == 0 { Task { await loadNextPatchPage() } }
        } catch {
            loadError = error
        }
    }

    private func apply(_ page: PullRequestPage) {
        let headMoved = self.page.map { $0.headRefOid != page.headRefOid } ?? true
        self.page = page
        loadedAt = .now
        // Later file pages and patches belong to the old head; start over when it moves.
        if headMoved || files.count <= page.files.count {
            files = page.files
            filesCursor = page.filesCursor
        } else {
            // Keep the pages loaded since, refreshing the viewed marks of the first hundred.
            let fresh = Dictionary(page.files.map { ($0.path, $0) }, uniquingKeysWith: { first, _ in first })
            files = files.map { fresh[$0.path] ?? $0 }
        }
        if headMoved {
            patches = [:]
            hunks = [:]
            highlighted = [:]
            highlightedPaths = []
            lineCounts = [:]
            largeDiffs = []
            blockTexts = [:]
            patchPagesLoaded = 0
            patchesComplete = false
            checks = nil
        }
    }

    func loadMoreTimeline() async {
        guard let gitHub, let cursor = page?.timelineCursor, !isLoadingMoreTimeline else { return }
        isLoadingMoreTimeline = true
        defer { isLoadingMoreTimeline = false }
        do {
            let next = try await gitHub.cli().timeline(reference, after: cursor)
            page?.timeline += next.items
            page?.timelineCursor = next.next
        } catch {
            actionError = error
        }
    }

    func loadChecks(force: Bool = false) async {
        guard let gitHub, force || checks == nil, !isLoadingChecks else { return }
        isLoadingChecks = true
        defer { isLoadingChecks = false }
        do {
            checks = try await gitHub.cli().forPullRequest(reference).checks(.number(reference.number), in: location)
            checksError = nil
        } catch {
            checksError = error
        }
    }

    /// Where gh finds the repository without a local checkout.
    var location: RepositoryLocation {
        .remote(reference.host == "github.com" ? reference.repository : "\(reference.host)/\(reference.repository)")
    }

    // MARK: - Threads

    func threads(in path: String) -> [ReviewThread] {
        page?.threads.filter { $0.path == path } ?? []
    }

    /// Unresolved threads per file, for the tree.
    var openThreadCounts: [String: Int] {
        Dictionary(grouping: (page?.threads ?? []).filter { !$0.isResolved }, by: \.path).mapValues(\.count)
    }

    /// The viewer's pending comments, which submitting the review publishes.
    var pendingCommentCount: Int {
        page?.threads.reduce(0) { $0 + $1.comments.filter(\.isPending).count } ?? 0
    }

    func open(_ url: URL) {
        gitHub?.openExternally(url)
    }
}
