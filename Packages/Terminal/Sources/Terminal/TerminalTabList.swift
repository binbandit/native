import Foundation

/// What a terminal tab's shell is doing.
public enum TerminalStatus: Hashable, Sendable {
    case running
    /// The shell ended (`exit`, ⌃D, or its process was killed).
    case exited
    case failedToStart(TerminalStartFailure)

    /// How long a shell has to run before its exit counts as normal rather than a failed start;
    /// Ghostty's `abnormal-command-exit-runtime` default.
    public static let failedStartThreshold: Duration = .milliseconds(250)

    /// The status of a shell that ran for `runtime` and then exited.
    public init(exitedAfter runtime: Duration) {
        self = runtime <= Self.failedStartThreshold ? .failedToStart(.exitedImmediately) : .exited
    }
}

/// Why a terminal's shell never ran.
public enum TerminalStartFailure: Error, Hashable, Sendable {
    /// The folder it was to start in is gone, such as a task worktree that was removed.
    case directoryMissing
    /// The shell at this path isn't there or can't be run.
    case shellNotFound(String)
    /// The shell ended right after starting: a broken profile, or a command that doesn't exist.
    case exitedImmediately
    /// The terminal engine couldn't create the terminal.
    case engineFailed
}

/// One task's terminal tabs: their order, names and which one is showing.
public struct TerminalTabList: Hashable, Sendable {
    public struct Tab: Identifiable, Hashable, Sendable {
        public let id: UUID
        /// Names the tab until its shell sets a title; the lowest number not in use.
        public let number: Int
        /// The title the shell or program set (OSC 0/2), such as the directory or running command.
        public var title: String?
        public var status: TerminalStatus = .running
        /// The command the tab runs instead of a shell, when it runs one; it names the tab.
        public var job: TerminalJob?
        /// A foreground command is running, as reported by the terminal engine's shell integration.
        public var isCommandRunning = false
        /// The last shell command's exit status. Cleared when another command starts.
        public var lastCommandExitStatus: Int32?

        /// "Terminal", "Terminal 2", ..., the job's name, or the shell's title once it sets one.
        public var displayTitle: String {
            if let job {
                return job.name
            }
            if let title, !title.trimmingCharacters(in: .whitespaces).isEmpty {
                return title
            }
            return number == 1 ? "Terminal" : "Terminal \(number)"
        }
    }

    public private(set) var tabs: [Tab] = []
    public private(set) var selectedID: UUID?

    public init() {}

    public var selected: Tab? {
        tabs.first { $0.id == selectedID }
    }

    public var isEmpty: Bool { tabs.isEmpty }

    public var activity: TerminalActivitySummary {
        TerminalActivitySummary(tabs: tabs)
    }

    /// What a tab's button says: its display title, numbered when another tab shows the same one
    /// (two shells in the same folder, say).
    public func label(of tab: Tab) -> String {
        let title = tab.displayTitle
        let isShared = tabs.contains { $0.id != tab.id && $0.displayTitle == title }
        return isShared ? "\(title) · \(tab.number)" : title
    }

    /// Adds a tab after the others and selects it.
    @discardableResult
    public mutating func add(id: UUID = UUID(), job: TerminalJob? = nil) -> Tab {
        let used = Set(tabs.map(\.number))
        let number = (1...).first { !used.contains($0) } ?? tabs.count + 1
        let tab = Tab(id: id, number: number, job: job)
        tabs.append(tab)
        selectedID = id
        return tab
    }

    public mutating func select(_ id: UUID) {
        guard tabs.contains(where: { $0.id == id }) else { return }
        selectedID = id
    }

    /// Removes a tab. Closing the selected tab selects its right neighbor, or the left one when it
    /// was last, the way closing a tab works everywhere else on the Mac.
    public mutating func close(_ id: UUID) {
        guard let index = tabs.firstIndex(where: { $0.id == id }) else { return }
        tabs.remove(at: index)
        guard selectedID == id else { return }
        selectedID = tabs.isEmpty ? nil : tabs[min(index, tabs.count - 1)].id
    }

    /// Selects the tab `offset` places after the selected one, wrapping around.
    public mutating func selectTab(offset: Int) {
        guard let selectedID, let index = tabs.firstIndex(where: { $0.id == selectedID }), !tabs.isEmpty else { return }
        let count = tabs.count
        self.selectedID = tabs[((index + offset) % count + count) % count].id
    }

    public mutating func setTitle(_ title: String?, of id: UUID) {
        guard let index = tabs.firstIndex(where: { $0.id == id }) else { return }
        tabs[index].title = title
    }

    public mutating func setStatus(_ status: TerminalStatus, of id: UUID) {
        guard let index = tabs.firstIndex(where: { $0.id == id }) else { return }
        tabs[index].status = status
        if status != .running {
            tabs[index].isCommandRunning = false
        }
    }

    public mutating func setCommandRunning(_ running: Bool, of id: UUID) {
        guard let index = tabs.firstIndex(where: { $0.id == id }), tabs[index].status == .running else { return }
        if running && !tabs[index].isCommandRunning {
            tabs[index].lastCommandExitStatus = nil
        }
        tabs[index].isCommandRunning = running
    }

    public mutating func finishCommand(status: Int32, in id: UUID) {
        guard let index = tabs.firstIndex(where: { $0.id == id }) else { return }
        tabs[index].isCommandRunning = false
        // libghostty uses -1 when shell integration did not report a status.
        tabs[index].lastCommandExitStatus = status >= 0 ? status : nil
    }

    public mutating func resetCommand(in id: UUID) {
        guard let index = tabs.firstIndex(where: { $0.id == id }) else { return }
        tabs[index].isCommandRunning = false
        tabs[index].lastCommandExitStatus = nil
    }

    /// The tab that runs the job with this key, running or finished.
    public func tab(forJob key: String) -> Tab? {
        tabs.first { $0.job?.key == key }
    }

    public mutating func updateJob(of id: UUID, _ change: (inout TerminalJob) -> Void) {
        guard let index = tabs.firstIndex(where: { $0.id == id }), var job = tabs[index].job else { return }
        change(&job)
        tabs[index].job = job
    }

    public mutating func setJob(_ job: TerminalJob?, of id: UUID) {
        guard let index = tabs.firstIndex(where: { $0.id == id }) else { return }
        tabs[index].job = job
    }
}
