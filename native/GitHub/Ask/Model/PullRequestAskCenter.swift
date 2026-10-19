import Foundation
import GitHub
import Observation

/// Private questions about pull requests, for the app's lifetime: each pull request's
/// conversation, and whether its page shows the panel. Connected by the composition root
/// (`PullRequestAskWiring`); until then the entry points stay hidden.
@Observable
final class PullRequestAskCenter {
    /// Pull requests whose page shows the panel.
    private(set) var openPanels: Set<PullRequestReference> = []
    @ObservationIgnored private(set) weak var app: AppModel?
    @ObservationIgnored private(set) weak var gitHub: GitHubModel?
    @ObservationIgnored var records = PullRequestAskRecords()
    @ObservationIgnored private var conversations: [PullRequestReference: PullRequestAskConversation] = [:]

    var isConnected: Bool {
        app != nil && gitHub != nil
    }

    func connect(app: AppModel, gitHub: GitHubModel) {
        self.app = app
        self.gitHub = gitHub
    }

    func conversation(for reference: PullRequestReference) -> PullRequestAskConversation {
        if let conversation = conversations[reference] { return conversation }
        let conversation = PullRequestAskConversation(reference: reference, record: records[reference], center: self)
        conversations[reference] = conversation
        return conversation
    }

    // MARK: - The panel

    func isPanelOpen(for reference: PullRequestReference) -> Bool {
        openPanels.contains(reference)
    }

    func setPanelOpen(_ isOpen: Bool, for reference: PullRequestReference) {
        if isOpen {
            openPanels.insert(reference)
        } else {
            openPanels.remove(reference)
        }
    }

    func togglePanel(for reference: PullRequestReference) {
        setPanelOpen(!isPanelOpen(for: reference), for: reference)
    }

    /// "Ask About This PR…": the pull request's page with the panel open, wherever the user was.
    func ask(about reference: PullRequestReference) {
        setPanelOpen(true, for: reference)
        conversation(for: reference).wantsComposerFocus = true
        gitHub?.open(reference)
    }

    /// Opens a conversation that search found on its pull request's page, rather than as a task in
    /// the sidebar. Returns whether `key` was one.
    func openSearched(_ key: SessionKey) -> Bool {
        guard let reference = records.reference(of: key) else { return false }
        setPanelOpen(true, for: reference)
        gitHub?.open(reference)
        Task { await conversation(for: reference).restore() }
        return true
    }

    // MARK: - Folders

    /// Where a pull request's conversation runs and keeps its saved copy:
    /// `Application Support/<bundle id>/PullRequestQuestions/<host>/<owner>/<name>-<number>`. Named
    /// so that whatever shows a session's folder (Usage, search) reads as the pull request.
    func folder(for reference: PullRequestReference) -> URL {
        URL.applicationSupportDirectory
            .appending(path: Bundle.main.bundleIdentifier ?? "Native", directoryHint: .isDirectory)
            .appending(path: "PullRequestQuestions", directoryHint: .isDirectory)
            .appending(path: reference.host, directoryHint: .isDirectory)
            .appending(path: reference.owner, directoryHint: .isDirectory)
            .appending(path: "\(reference.name)-\(reference.number)", directoryHint: .isDirectory)
    }
}
