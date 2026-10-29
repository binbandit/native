import Foundation

/// A short, factual description of the current turn. It never interprets command output as
/// progress: the plan is the only counted work ACP currently reports with a known denominator.
public struct TaskActivityNarration: Equatable, Sendable {
    public var verb: String
    public var object: String?
    /// The object is code (a file, a command), which some places set in code type.
    public var objectIsCode = false
    public var progress: Progress?

    public struct Progress: Equatable, Sendable {
        public let completed: Int
        public let total: Int

        public init?(completed: Int, total: Int) {
            guard total > 0, completed >= 0, completed <= total else { return nil }
            self.completed = completed
            self.total = total
        }
    }

    public init(verb: String, object: String? = nil, progress: Progress? = nil) {
        self.verb = verb
        self.object = object
        self.progress = progress
    }

    public init(items: some BidirectionalCollection<TranscriptItem>, plan: [PlanEntry]) {
        let call = items.reversed().lazy.compactMap { item -> ToolCallState? in
            guard case .toolCall(let call) = item, !call.status.isFinished else { return nil }
            return call
        }.first
        if let call {
            // The transcript's own words for the call, so the two never disagree.
            let wording = call.wording
            verb = wording.verb?.progressive ?? (wording.category == .mcp ? "Using" : "Working")
            object = wording.object
            objectIsCode = wording.objectIsCode
        } else {
            verb = "Working"
            object = nil
        }
        // These are plan steps, never a claim about tests or the currently running tool.
        if plan.contains(where: { $0.status != .completed }) {
            progress = Progress(completed: plan.count { $0.status == .completed }, total: plan.count)
        }
    }
}

extension SessionState {
    /// Only the live turn can narrate work. Replayed tools and earlier unfinished calls do not
    /// become today's activity when a task is opened or a new turn starts.
    public var taskActivity: TaskActivityNarration {
        guard let openTurn else { return TaskActivityNarration(verb: "Working") }
        // The reducer already indexes open calls. Streaming a long reply must not rescan the turn.
        let latest = openCallIndices.filter { $0 >= openTurn }.max()
        return TaskActivityNarration(
            items: latest.map { [items[$0]] } ?? [], plan: planTurnStart == openTurn ? plan : [])
    }
}
