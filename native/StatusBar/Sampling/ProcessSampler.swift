import Darwin
import Foundation

/// Samples memory and CPU of Native and its agents' process trees with libproc. A sample costs a
/// few syscalls per process and spawns nothing (no `ps` per sweep), so it can run
/// every couple of seconds.
actor ProcessSampler {
    /// A tree to report on: its root process and how to label it.
    struct Root: Hashable, Sendable {
        let pid: Int32
        let kind: ProcessGroup.Kind
        let title: String
    }

    /// A process's identity across samples. Pids get reused; a pid with a new start time is a new
    /// process.
    private struct Identity: Hashable {
        let pid: Int32
        let start: UInt64
    }

    private struct Reading {
        let pid: Int32
        let identity: Identity
        let memory: UInt64
        /// User plus system time, in nanoseconds.
        let cpuTime: UInt64
    }

    private var previous: [Identity: (cpuTime: UInt64, at: UInt64)] = [:]
    private var names: [Identity: String] = [:]
    private let timebase: (numer: UInt64, denom: UInt64) = {
        var info = mach_timebase_info()
        mach_timebase_info(&info)
        return (UInt64(info.numer), UInt64(max(info.denom, 1)))
    }()

    /// Samples Native, each agent tree in `agents`, and Native's other descendants.
    func sample(agents: [Root]) -> ResourceSnapshot {
        let now = mach_absolute_time()
        let app = getpid()
        var claimed: Set<Int32> = [app]
        var groups = [
            group(for: Root(pid: app, kind: .app, title: "Native"), descendants: false, claimed: &claimed, now: now)
        ]
        for agent in agents where !claimed.contains(agent.pid) {
            groups.append(group(for: agent, descendants: true, claimed: &claimed, now: now))
        }
        // Whatever else Native started: shells resolving the environment, git, helpers.
        let others = tree(from: app, excluding: claimed).dropFirst().compactMap {
            usage(of: $0.pid, depth: $0.depth - 1, now: now)
        }
        if !others.isEmpty {
            groups.append(ProcessGroup(kind: .other, title: "Other", processes: others))
        }
        forgetExited(keeping: Set(groups.flatMap { $0.processes.map(\.pid) }))
        return ResourceSnapshot(date: .now, groups: groups.filter { !$0.processes.isEmpty })
    }

    private func group(for root: Root, descendants: Bool, claimed: inout Set<Int32>, now: UInt64) -> ProcessGroup {
        let members = descendants ? tree(from: root.pid, excluding: claimed) : [(root.pid, 0)]
        claimed.formUnion(members.map(\.pid))
        let processes = members.compactMap { usage(of: $0.pid, depth: $0.depth, now: now) }
        return ProcessGroup(kind: root.kind, title: root.title, processes: processes)
    }

    /// `root` and its descendants depth-first, skipping `excluded` subtrees.
    private func tree(from root: Int32, excluding excluded: Set<Int32>) -> [(pid: Int32, depth: Int)] {
        var result: [(Int32, Int)] = []
        var stack: [(Int32, Int)] = [(root, 0)]
        while let (pid, depth) = stack.popLast() {
            result.append((pid, depth))
            // Reversed so the stack pops children in pid order.
            for child in children(of: pid).reversed() where !excluded.contains(child) {
                stack.append((child, depth + 1))
            }
        }
        return result
    }

    private func children(of pid: Int32) -> [Int32] {
        var capacity = 32
        while true {
            var buffer = [pid_t](repeating: 0, count: capacity)
            let count = Int(proc_listchildpids(pid, &buffer, Int32(capacity * MemoryLayout<pid_t>.size)))
            guard count > 0 else { return [] }
            // A full buffer may have been cut short.
            if count < capacity || capacity >= 4096 {
                return Array(buffer.prefix(count)).sorted()
            }
            capacity *= 4
        }
    }

    private func usage(of pid: Int32, depth: Int, now: UInt64) -> ProcessUsage? {
        guard let reading = read(pid) else { return nil }
        var cpu: Double?
        if let last = previous[reading.identity], now > last.at, reading.cpuTime >= last.cpuTime {
            let wall = Double(ticksToNanoseconds(now - last.at))
            cpu = Double(reading.cpuTime - last.cpuTime) / wall * 100
        }
        previous[reading.identity] = (reading.cpuTime, now)
        return ProcessUsage(
            pid: pid,
            name: name(of: reading.identity),
            depth: depth,
            memory: reading.memory,
            cpu: cpu
        )
    }

    private func read(_ pid: Int32) -> Reading? {
        var info = rusage_info_v4()
        let result = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) { proc_pid_rusage(pid, RUSAGE_INFO_V4, $0) }
        }
        guard result == 0 else { return nil }
        return Reading(
            pid: pid,
            identity: Identity(pid: pid, start: info.ri_proc_start_abstime),
            memory: info.ri_phys_footprint,
            // On Apple silicon these are mach ticks, not nanoseconds.
            cpuTime: ticksToNanoseconds(info.ri_user_time + info.ri_system_time)
        )
    }

    private func name(of identity: Identity) -> String {
        if let name = names[identity] {
            return name
        }
        let name = ProcessNaming.name(
            arguments: Self.arguments(of: identity.pid), fallback: Self.shortName(of: identity.pid))
        names[identity] = name
        return name
    }

    private func forgetExited(keeping live: Set<Int32>) {
        previous = previous.filter { live.contains($0.key.pid) }
        names = names.filter { live.contains($0.key.pid) }
    }

    private func ticksToNanoseconds(_ ticks: UInt64) -> UInt64 {
        ticks.multipliedReportingOverflow(by: timebase.numer).overflow
            ? ticks / timebase.denom * timebase.numer
            : ticks * timebase.numer / timebase.denom
    }

    private static func shortName(of pid: Int32) -> String {
        var buffer = [CChar](repeating: 0, count: 256)
        guard proc_name(pid, &buffer, UInt32(buffer.count)) > 0 else { return "pid \(pid)" }
        return String(decoding: buffer.prefix { $0 != 0 }.map(UInt8.init(bitPattern:)), as: UTF8.self)
    }

    /// The process's argv, from `KERN_PROCARGS2`: argc, the executable path, padding, then argv.
    private static func arguments(of pid: Int32) -> [String] {
        var mib: [Int32] = [CTL_KERN, KERN_PROCARGS2, pid]
        var size = 0
        guard sysctl(&mib, 3, nil, &size, nil, 0) == 0, size > MemoryLayout<Int32>.size else { return [] }
        var buffer = [UInt8](repeating: 0, count: size)
        guard sysctl(&mib, 3, &buffer, &size, nil, 0) == 0 else { return [] }
        let argc = buffer.withUnsafeBytes { $0.loadUnaligned(as: Int32.self) }
        var index = MemoryLayout<Int32>.size
        // Skip the executable path and the NULs after it.
        while index < size, buffer[index] != 0 { index += 1 }
        while index < size, buffer[index] == 0 { index += 1 }
        var arguments: [String] = []
        while arguments.count < argc, index < size {
            let start = index
            while index < size, buffer[index] != 0 { index += 1 }
            arguments.append(String(decoding: buffer[start..<index], as: UTF8.self))
            index += 1
        }
        return arguments
    }
}
