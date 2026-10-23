import Foundation

#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

/// Processes observed beneath a process Native launched. Start times keep a recycled pid out of
/// the stop, and retaining children before sending cancel keeps ownership after reparenting.
/// A child can fork and exit entirely between snapshots. This tracks known processes, never proof
/// that no detached descendant exists; the caller must report that limit instead of Stopped.
struct AgentStopProcesses: Sendable {
    private struct ProcessIdentity: Sendable {
        var pid: pid_t
        var parent: pid_t
        var started: UInt64
        var stopped: Bool
        var exited: Bool
    }

    private var owned: [pid_t: ProcessIdentity] = [:]
    private var unreadable: Set<pid_t> = []

    init(root: pid_t) {
        if let identity = Self.read(root) {
            owned[root] = identity
        } else if !Self.isGone(root) {
            unreadable.insert(root)
        }
        refresh()
    }

    var hasRemainingProcesses: Bool { !owned.isEmpty || !unreadable.isEmpty }

    /// Also follows previously seen children: cancel can make the parent exit before its shell.
    mutating func refresh() {
        unreadable = unreadable.filter { !Self.isGone($0) }
        owned = owned.filter { _, identity in
            guard let current = Self.read(identity.pid) else { return !Self.isGone(identity.pid) }
            return current.started == identity.started && !current.exited
        }
        var frontier = Array(owned.values)
        var visited: Set<pid_t> = []
        while let parent = frontier.popLast() {
            guard visited.insert(parent.pid).inserted, matches(parent) else { continue }
            guard let children = Self.children(of: parent.pid) else {
                unreadable.insert(parent.pid)
                continue
            }
            unreadable.remove(parent.pid)
            // The parent may have exited while the kernel enumerated its children.
            guard matches(parent) else { continue }
            for pid in children {
                guard let child = Self.read(pid) else {
                    if !Self.isGone(pid) { unreadable.insert(pid) }
                    continue
                }
                guard child.parent == parent.pid, !child.exited else { continue }
                unreadable.remove(pid)
                owned[pid] = child
                frontier.append(child)
            }
        }
    }

    /// Called after the agent's own cancel grace period. Freeze parents and children before the
    /// final enumeration, so no shell can fork another writer while its tree is being killed.
    /// The caller keeps the task Stopping and polls until every owned process has exited.
    mutating func terminate() {
        refresh()
        for identity in owned.values where matches(identity) {
            _ = kill(identity.pid, SIGSTOP)
        }
        refresh()
        guard unreadable.isEmpty,
            owned.values.allSatisfy({ identity in
                guard let current = Self.read(identity.pid) else { return Self.isGone(identity.pid) }
                return current.started != identity.started || current.exited || current.stopped
            })
        else { return }
        for identity in owned.values where matches(identity) {
            _ = kill(identity.pid, SIGKILL)
        }
        refresh()
    }

    private func matches(_ identity: ProcessIdentity) -> Bool {
        guard let current = Self.read(identity.pid) else { return false }
        return current.started == identity.started && !current.exited
    }

    private static func isGone(_ pid: pid_t) -> Bool {
        kill(pid, 0) != 0 && errno == ESRCH
    }

    private static func read(_ pid: pid_t) -> ProcessIdentity? {
        #if canImport(Darwin)
        var info = proc_bsdinfo()
        let size = MemoryLayout<proc_bsdinfo>.size
        guard proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, Int32(size)) == Int32(size) else { return nil }
        return ProcessIdentity(
            pid: pid, parent: pid_t(info.pbi_ppid),
            started: info.pbi_start_tvsec * 1_000_000 + info.pbi_start_tvusec,
            stopped: info.pbi_status == UInt32(SSTOP), exited: info.pbi_status == UInt32(SZOMB))
        #elseif os(Linux)
        guard let stat = try? String(contentsOfFile: "/proc/\(pid)/stat", encoding: .utf8),
            let command = stat.lastIndex(of: ")")
        else { return nil }
        let fields = stat[stat.index(after: command)...].split(separator: " ")
        guard fields.count > 19, let parent = pid_t(fields[1]), let started = UInt64(fields[19]) else { return nil }
        return ProcessIdentity(
            pid: pid, parent: parent, started: started,
            stopped: fields[0] == "T" || fields[0] == "t", exited: fields[0] == "Z" || fields[0] == "X")
        #else
        return nil
        #endif
    }

    private static func children(of parent: pid_t) -> [pid_t]? {
        #if canImport(Darwin)
        var capacity = 64
        while true {
            var children = [pid_t](repeating: 0, count: capacity)
            let count = proc_listchildpids(parent, &children, Int32(capacity * MemoryLayout<pid_t>.size))
            guard count >= 0 else { return nil }
            if count < capacity { return Array(children.prefix(Int(count))).filter { $0 > 0 } }
            capacity *= 2
        }
        #elseif os(Linux)
        guard let entries = try? FileManager.default.contentsOfDirectory(atPath: "/proc") else { return nil }
        return entries.compactMap { entry in
            guard let pid = pid_t(entry), let child = read(pid), child.parent == parent else { return nil }
            return pid
        }
        #else
        return nil
        #endif
    }
}
