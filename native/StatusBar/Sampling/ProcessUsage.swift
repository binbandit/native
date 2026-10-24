import Exec
import Foundation

/// One process's resource use at a sample.
nonisolated struct ProcessUsage: Identifiable, Hashable, Sendable {
    let pid: Int32
    /// A readable name, such as "claude-agent-acp" for a node process running that package.
    let name: String
    /// How far below its group's root the process is, for indenting.
    let depth: Int
    /// Physical footprint in bytes: what Activity Monitor's Memory column shows.
    let memory: UInt64
    /// Percent of the sampling machine's total CPU capacity (0 to 100) over the last interval.
    /// Nil on a process's first sample.
    let cpu: Double?

    var id: Int32 { pid }
}

/// A process tree the status bar reports on: Native itself, one per agent, and the rest of
/// Native's children.
nonisolated struct ProcessGroup: Identifiable, Hashable, Sendable {
    enum Kind: Hashable, Sendable {
        case app
        /// By the agent's id (`AgentDefinition.ID.rawValue`).
        case agent(String)
        /// Native's descendants outside the agents' trees (shells, git, MCP helpers).
        case other
    }

    let kind: Kind
    let title: String
    /// Root first, then its descendants depth-first.
    let processes: [ProcessUsage]

    var id: Kind { kind }

    var memory: UInt64 {
        processes.reduce(0) { $0 + $1.memory }
    }

    var cpu: Double {
        ProcessCPUUsage.total(processes.compactMap(\.cpu))
    }
}

/// Everything sampled at one moment.
nonisolated struct ResourceSnapshot: Hashable, Sendable {
    let date: Date
    let groups: [ProcessGroup]

    static let empty = ResourceSnapshot(date: .distantPast, groups: [])

    var memory: UInt64 {
        groups.reduce(0) { $0 + $1.memory }
    }

    var cpu: Double {
        ProcessCPUUsage.total(groups.map(\.cpu))
    }

    var processCount: Int {
        groups.reduce(0) { $0 + $1.processes.count }
    }

    func group(_ kind: ProcessGroup.Kind) -> ProcessGroup? {
        groups.first { $0.kind == kind }
    }
}
