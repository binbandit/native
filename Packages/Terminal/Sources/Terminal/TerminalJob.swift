import Foundation

/// A command a tab runs in place of a shell, such as a project action: what names the tab, and how
/// its latest run went. Running the same job again (the same `key`) reuses its tab.
public struct TerminalJob: Hashable, Sendable {
    /// What identifies the job across runs, such as a project action's id.
    public let key: String
    /// The tab's name while the job has it ("Test").
    public var name: String
    /// What it runs, as the user wrote it, for the tab's notices.
    public var command: String
    public var startedAt: Date
    /// How the run ended; nil while it's running.
    public var outcome: Outcome?
    /// Stop was asked for and the program interrupted; the run counts as stopped when it ends.
    public var isStopping = false

    public init(key: String, name: String, command: String, startedAt: Date = .now) {
        self.key = key
        self.name = name
        self.command = command
        self.startedAt = startedAt
    }

    public var isRunning: Bool { outcome == nil }

    public enum Outcome: Hashable, Sendable {
        /// It ended on its own, with its exit status when the terminal reported one.
        case exited(status: Int32?, duration: Duration)
        /// The user stopped it.
        case stopped(duration: Duration)

        public var succeeded: Bool {
            if case .exited(status: 0, _) = self { true } else { false }
        }

        public var duration: Duration {
            switch self {
            case .exited(_, let duration), .stopped(let duration): duration
            }
        }
    }

    /// Records how the run ended. A command that reported its status ends with that status and
    /// duration; one that didn't (it was killed, or its shell exited first) with the time since it
    /// started. Stopping wins over a failing status, since the interrupt is what failed it.
    public mutating func finish(status: Int32?, duration: Duration? = nil, now: Date = .now) {
        guard isRunning else { return }
        let elapsed = duration ?? .seconds(max(0, now.timeIntervalSince(startedAt)))
        outcome = isStopping && status != 0 ? .stopped(duration: elapsed) : .exited(status: status, duration: elapsed)
    }
}
