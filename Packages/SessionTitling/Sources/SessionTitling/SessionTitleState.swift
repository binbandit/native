import AIInstructions
import Foundation

/// One task's title as Native keeps it: the user's own, the one generated from its first message,
/// and, while a title is still wanted, what it's written from. The host runs these transitions and
/// stores the result (docs/durability.md, "Titles"); clients show `displayTitle(agentTitle:)`.
///
/// The user's title always wins. A weak automatic title may be refined once after the first
/// turn. Revision checks prevent late answers from replacing that refinement.
public struct SessionTitleState: Hashable, Sendable {
    public enum Progress: String, Hashable, Sendable {
        /// The host's own generator is writing it.
        case generating
        /// The host can't write it (no model on that machine, or the titler runs only in clients):
        /// the next client with a titler does.
        case waitingForClient
        /// The generator tried and couldn't. The next turn may retry once; the first message
        /// names the task meanwhile.
        case failed
    }

    /// Persisted so reconnects, undo and restarts cannot replenish the refinement budget.
    public private(set) var refinementCount: Int
    public private(set) var firstTurnFinished: Bool
    public private(set) var wasRenamed: Bool
    public var user: String?
    public var generated: String?
    /// The first message, kept from when a title is wanted until one is generated, so a host that
    /// restarts or a client that attaches later can finish the job. Its `instructions` aren't
    /// kept: they're the ones in effect when the title is written.
    public var request: SessionTitleRequest?
    public var progress: Progress?
    /// Kept by the host so reconnecting or restarting cannot replenish the retry budget.
    public private(set) var retryCount: Int
    /// The logical prompt that first requested a title. Recovery may resend it after a restart.
    public private(set) var promptID: UUID?

    public init(
        user: String? = nil, generated: String? = nil, request: SessionTitleRequest? = nil, progress: Progress? = nil,
        retryCount: Int = 0, promptID: UUID? = nil, refinementCount: Int = 0,
        firstTurnFinished: Bool = false, wasRenamed: Bool = false
    ) {
        self.refinementCount = refinementCount
        self.firstTurnFinished = firstTurnFinished
        self.wasRenamed = wasRenamed || user != nil
        self.user = user
        self.generated = generated
        self.request = request
        self.progress = progress
        self.retryCount = retryCount
        self.promptID = promptID
    }

    public var isEmpty: Bool {
        user == nil && generated == nil && request == nil && progress == nil && !wasRenamed && !firstTurnFinished
    }

    /// Whether the task's first message should start a title: nothing of Native's or the user's
    /// names it yet, and none was tried.
    public var wantsTitle: Bool {
        user == nil && !wasRenamed && generated == nil && progress == nil
    }

    /// Keep the task recognizable even while a slow model is still writing its title.
    public var fallback: String? {
        guard generated == nil else { return nil }
        return request.flatMap { SessionTitleRules.fallback(from: $0.prompt) }
    }

    public func displayTitle(agentTitle: String?) -> String? {
        SessionTitleRules.display(user: user, generated: generated, agent: agentTitle, fallback: fallback)
    }

    /// Called for each new turn. Empty first messages don't consume the opportunity to title a
    /// task. A failed or unavailable generator gets one more attempt, using the original request.
    @discardableResult
    public mutating func beginIfNeeded(
        _ request: SessionTitleRequest, promptID: UUID? = nil, allowsRetry: Bool = true
    ) -> Bool {
        guard user == nil, generated == nil else { return false }
        if wantsTitle {
            guard SessionTitleRules.fallback(from: request.prompt) != nil else { return false }
            begin(request, promptID: promptID)
            return true
        }
        guard allowsRetry, promptID == nil || promptID != self.promptID,
            retryCount == 0, self.request != nil, progress == .failed || progress == .waitingForClient
        else {
            return false
        }
        retryCount += 1
        progress = .generating
        return true
    }

    /// Starts titling from the task's first message. Long messages are kept only as far as a title
    /// is ever written from.
    public mutating func begin(_ request: SessionTitleRequest, promptID: UUID? = nil) {
        var request = request
        request.prompt = SessionTitleInput.prepared(request.prompt, limit: SessionTitlePrompt.requestLimit)
        request.instructions = nil
        self.request = request
        self.promptID = promptID
        progress = .generating
    }

    /// Leaves the title to a client: the host has no generator that can write it.
    public mutating func waitForClient() {
        guard request != nil else { return }
        progress = .waitingForClient
    }

    /// The generator couldn't write a title.
    public mutating func fail() {
        progress = .failed
    }

    /// Accepts an answer for the current revision, told apart from the project's other tasks.
    /// Returns true when consumed, including a refinement that keeps the same visible title.
    @discardableResult
    public mutating func accept(generated title: String, distinctFrom others: [String] = [], revision: Int = 0) -> Bool
    {
        guard revision == refinementCount,
            generated == nil
                || (revision == 1 && request != nil && (progress == .generating || progress == .waitingForClient)),
            !(revision == 1 && wasRenamed)
        else { return false }
        let candidate =
            request.map { SessionTitleRules.automatic(title, from: $0) }
            ?? SessionTitleRules.cleaned(title).flatMap { SessionTitleInput.isSafeTitle($0) ? $0 : nil }
        guard let title = candidate else { return false }
        let prompt = request?.prompt ?? ""
        if revision == 1, SessionTitleRules.isWeak(title, projectName: request?.projectName ?? "") {
            request = nil
            progress = nil
            return true
        }
        generated = SessionTitleRules.distinct(title, from: others, prompt: prompt)
        progress = nil
        if wasRenamed || revision == 1
            || !(SessionTitleRules.isWeak(title, projectName: request?.projectName ?? "")
                || SessionTitleRules.needsOutcome(prompt, projectName: request?.projectName ?? ""))
        {
            request = nil
        } else if firstTurnFinished {
            if request?.firstTurnOutcome != nil { beginRefinementIfNeeded() } else { request = nil }
        }
        return true
    }

    /// Called only for the first completed turn. A slow initial generator can finish afterwards;
    /// accepting its weak result will then start the same single refinement.
    public mutating func finishFirstTurn(outcome: String) {
        guard !firstTurnFinished else { return }
        firstTurnFinished = true
        guard !wasRenamed, request != nil else { return }
        let outcome = SessionTitleInput.prepared(outcome, limit: 800)
        guard !outcome.isEmpty else {
            if generated != nil { request = nil; progress = nil }
            return
        }
        request?.firstTurnOutcome = outcome
        beginRefinementIfNeeded()
    }

    private mutating func beginRefinementIfNeeded() {
        guard !wasRenamed, user == nil, refinementCount == 0, request?.firstTurnOutcome != nil,
            let generated,
            SessionTitleRules.isWeak(generated, projectName: request?.projectName ?? "")
                || SessionTitleRules.needsOutcome(request?.prompt ?? "", projectName: request?.projectName ?? "")
        else { return }
        refinementCount = 1
        progress = .generating
    }

    /// Sets the user's own title; nil or empty goes back to the automatic one. Returns whether
    /// anything changed.
    @discardableResult
    public mutating func rename(to title: String?) -> Bool {
        let title = SessionTitleRules.userTitle(title)
        guard title != user else { return false }
        user = title
        if title != nil {
            wasRenamed = true
            if generated != nil { request = nil; progress = nil }
        }
        return true
    }
}
