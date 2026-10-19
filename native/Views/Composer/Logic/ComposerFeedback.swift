import Foundation

/// What just happened to the user's last action in the composer, shown for a moment where they
/// took it (docs/product-quality.md: every action says what it did).
struct ComposerFeedback: Equatable, Identifiable {
    enum Tone {
        case done, notice, problem
    }

    let id = UUID()
    let tone: Tone
    let message: String
    /// Whether the line offers Undo; ⌘Z does the same.
    var canUndo = false

    /// How long it stays: long enough to read, longer when it can be undone.
    var duration: Duration {
        canUndo ? .seconds(6) : .seconds(4)
    }

    /// What became of a sent message. One that started a turn of its own shows in the transcript, so
    /// it needs no word here. `wasWorking` says whether a turn was running; otherwise the agent
    /// wasn't ready yet (the session was loading), or `heldFor` names what its turns wait for.
    init?(
        delivery: SessionModel.FollowUpDelivery, requested: FollowUpBehavior, wasWorking: Bool, supportsSteering: Bool,
        agentName: String, heldFor hold: String? = nil
    ) {
        switch delivery {
        case .prompted:
            return nil
        case .queued where !wasWorking && hold != nil:
            self.init(tone: .done, message: "Sends once \(hold ?? "") is done")
        case .queued where !wasWorking:
            self.init(tone: .done, message: "Sends when \(agentName) is ready")
        case .steered:
            self.init(tone: .done, message: "Added to the running turn")
        case .queued where requested == .steer && !supportsSteering:
            self.init(
                tone: .notice,
                message: "Queued: \(agentName) can’t join a running turn, so it goes when this one ends")
        case .queued where requested == .steer:
            self.init(tone: .notice, message: "Queued: the turn ended before it could join, so it goes next")
        case .queued:
            self.init(tone: .done, message: "Queued: it goes when this turn ends")
        }
    }

    /// A queued message sent ahead of the rest. One sent as the next prompt shows in the transcript.
    init?(sendingNow route: SessionModel.SendNowRoute, agentName: String) {
        switch route {
        case .steer: self.init(tone: .done, message: "Adding it to the running turn")
        case .interrupt: self.init(tone: .notice, message: "Stopping \(agentName)’s turn, then sending it")
        case .send: return nil
        }
    }

    init(tone: Tone, message: String, canUndo: Bool = false) {
        self.tone = tone
        self.message = message
        self.canUndo = canUndo
    }

    static func blocked(_ reason: String) -> ComposerFeedback {
        ComposerFeedback(tone: .problem, message: reason)
    }

    static func failed(_ error: any Error) -> ComposerFeedback {
        ComposerFeedback(tone: .problem, message: "Couldn’t send: \(error.localizedDescription)")
    }

    static var removedFromQueue: ComposerFeedback {
        ComposerFeedback(tone: .done, message: "Removed from the queue", canUndo: true)
    }

    static var updatedInQueue: ComposerFeedback {
        ComposerFeedback(tone: .done, message: "Queued message updated")
    }

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.id == rhs.id
    }
}
