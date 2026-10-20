import Foundation

#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

/// The process groups an agent's processes run in, so stopping the agent ends all of them.
///
/// `Process` makes the launched command a group leader, so the agent and whatever it starts share
/// one group. Some launchers move their children into groups of their own (npm does), and those
/// children can outlive the launcher holding the agent's pipes; so the groups of the whole process
/// tree are noted while it's alive, and every noted group is signalled when the agent stops.
/// Signalling a group rather than a pid can't reach an unrelated process given a recycled pid: a
/// group's id isn't reused while anything in it is alive.
struct AgentProcessGroups: Sendable {
    private(set) var groups: Set<pid_t> = []

    /// Notes the launched process's group and its descendants' groups, as they are now.
    mutating func note(treeOf root: pid_t) {
        for pid in [root] + Self.descendants(of: root) {
            let group = getpgid(pid)
            if group > 1, group != getpgrp() {
                groups.insert(group)
            }
        }
    }

    /// Asks every noted group to stop, then kills what's left after `grace`.
    func end(grace: Duration = .seconds(2)) {
        let groups = groups.filter(Self.isAlive)
        guard !groups.isEmpty else { return }
        for group in groups {
            kill(-group, SIGTERM)
        }
        Task.detached {
            try? await Task.sleep(for: grace)
            for group in groups where Self.isAlive(group) {
                kill(-group, SIGKILL)
            }
        }
    }

    /// Ends every noted group before returning, for a host about to exit: no task outlives it to
    /// finish the job.
    func endNow(grace: Duration = .milliseconds(500)) {
        var groups = groups.filter(Self.isAlive)
        guard !groups.isEmpty else { return }
        for group in groups {
            kill(-group, SIGTERM)
        }
        let deadline = ContinuousClock.now + grace
        while !groups.isEmpty, ContinuousClock.now < deadline {
            usleep(20_000)
            groups = groups.filter(Self.isAlive)
        }
        for group in groups {
            kill(-group, SIGKILL)
        }
    }

    static func isAlive(_ group: pid_t) -> Bool {
        kill(-group, 0) == 0 || errno == EPERM
    }

    /// Every process under `root`, breadth first. Empty where the platform can't list children.
    static func descendants(of root: pid_t) -> [pid_t] {
        #if canImport(Darwin)
        var found: [pid_t] = []
        var frontier = [root]
        while let pid = frontier.popLast(), found.count < 1_000 {
            var children = [pid_t](repeating: 0, count: 256)
            let count = proc_listchildpids(pid, &children, Int32(children.count * MemoryLayout<pid_t>.size))
            let listed = children.prefix(Int(max(count, 0))).filter { $0 > 0 }
            found += listed
            frontier += listed
        }
        return found
        #elseif os(Linux)
        let children = Dictionary(grouping: parents()) { $0.parent }.mapValues { $0.map { $0.pid } }
        var found: [pid_t] = []
        var frontier = [root]
        while let pid = frontier.popLast(), found.count < 1_000 {
            let listed = children[pid] ?? []
            found += listed
            frontier += listed
        }
        return found
        #else
        return []
        #endif
    }

    #if os(Linux)
    /// Every process and its parent, from `/proc/<pid>/stat`. Read from every process rather than
    /// from `/proc/<pid>/task/*/children`, which only kernels built with it have.
    private static func parents() -> [(pid: pid_t, parent: pid_t)] {
        let entries = (try? FileManager.default.contentsOfDirectory(atPath: "/proc")) ?? []
        return entries.compactMap { entry in
            guard let pid = pid_t(entry),
                let stat = try? String(contentsOfFile: "/proc/\(entry)/stat", encoding: .utf8),
                let command = stat.lastIndex(of: ")")
            else { return nil }
            // After the command, which ends at its last ")", come the state and the parent's pid.
            let fields = stat[stat.index(after: command)...].split(separator: " ")
            guard fields.count > 1, let parent = pid_t(fields[1]) else { return nil }
            return (pid, parent)
        }
    }
    #endif
}
