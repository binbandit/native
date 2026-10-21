import AIInstructions
import Foundation

/// One task's title as Native keeps it: the user's own, the one generated from its first message,
/// and, while a title is still wanted, what it's written from. The host runs these transitions and
/// stores the result (docs/durability.md, "Titles"); clients show `displayTitle(agentTitle:)`.
///
/// The user's title always wins. A generated title is written once: the first to land stays, so a
/// host and a client that both wrote one never swap it under the user.
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
        retryCount: Int = 0, promptID: UUID? = nil
    ) {
        self.user = user
        self.generated = generated
        self.request = request
        self.progress = progress
        self.retryCount = retryCount
        self.promptID = promptID
    }

    public var isEmpty: Bool {
        user == nil && generated == nil && request == nil && progress == nil
    }

    /// Whether the task's first message should start a title: nothing of Native's or the user's
    /// names it yet, and none was tried.
    public var wantsTitle: Bool {
        user == nil && generated == nil && progress == nil
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
        request.prompt = String(request.prompt.prefix(SessionTitlePrompt.requestLimit))
        request.instructions = nil
        self.request = request
        self.promptID = promptID
        progress = .generating
    }

    /// Leaves the title to a client: the host has no generator that can write it.
    public mutating func waitForClient() {
        guard generated == nil, request != nil else { return }
        progress = .waitingForClient
    }

    /// The generator couldn't write a title.
    public mutating func fail() {
        guard generated == nil else { return }
        progress = .failed
    }

    /// Takes a generated title, in sentence case and told apart from `others` (the project's other
    /// live tasks), unless one landed first. Returns whether anything changed.
    @discardableResult
    public mutating func accept(generated title: String, distinctFrom others: [String] = []) -> Bool {
        guard generated == nil, let title = SessionTitleRules.cleaned(title) else { return false }
        let prompt = request?.prompt ?? ""
        generated = SessionTitleRules.distinct(
            SessionTitleRules.sentenceCase(title, keeping: prompt), from: others, prompt: prompt)
        request = nil
        progress = nil
        return true
    }

    /// Sets the user's own title; nil or empty goes back to the automatic one. Returns whether
    /// anything changed.
    @discardableResult
    public mutating func rename(to title: String?) -> Bool {
        let title = SessionTitleRules.userTitle(title)
        guard title != user else { return false }
        user = title
        return true
    }
}
