import Foundation

/// A short, factual description of the current turn. It never interprets command output as
/// progress: the plan is the only counted work ACP currently reports with a known denominator.
public struct TaskActivity: Equatable, Sendable {
    public var verb: String
    public var object: String?
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
            verb =
                switch call.kind {
                case .read: "Reading"
                case .edit: "Editing"
                case .delete: "Deleting"
                case .move: "Moving"
                case .search: "Searching"
                case .execute: "Running"
                case .fetch: "Fetching"
                case .think: "Thinking"
                case .switchMode, .other: "Working"
                }
            object =
                call.kind == .execute ? (call.shellCommand ?? call.title) : (call.locations.first?.path ?? call.title)
            if let value = object, value.lowercased().hasPrefix(verb.lowercased() + " ") {
                object = String(value.dropFirst(verb.count + 1))
            }
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
    public var taskActivity: TaskActivity {
        guard let openTurn else { return TaskActivity(verb: "Working") }
        // The reducer already indexes open calls. Streaming a long reply must not rescan the turn.
        let latest = openCallIndices.filter { $0 >= openTurn }.max()
        return TaskActivity(items: latest.map { [items[$0]] } ?? [], plan: plan)
    }
}
