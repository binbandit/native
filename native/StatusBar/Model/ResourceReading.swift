import Exec
import Foundation

/// What the status bar shows of a sample, to the precision it shows it. The monitor assigns a new
/// reading only when it differs, so an idle app's bar doesn't redraw for figures that didn't move.
///
/// Native and its agents are separate figures: the agents (and the MCP servers and tools they run)
/// usually use many times what Native does, and one total would read as Native's own.
struct ResourceReading: Hashable {
    struct Figures: Hashable {
        let memory: String
        let cpu: String
    }

    /// Native's own process.
    let app: Figures
    /// Everything Native started: agents with their MCP servers and tools, terminals, git. Nil
    /// while nothing runs.
    let agents: Figures?
    /// How much of the Mac's memory everything together takes.
    let pressure: MemoryPressure
    /// The tooltip and VoiceOver value: what each figure is, in words.
    let summary: String

    enum MemoryPressure: Hashable {
        case normal
        /// Past a quarter of the Mac's memory.
        case high
        /// Past half of it.
        case critical
    }

    /// Before the first sample.
    static let measuring = ResourceReading(
        app: Figures(memory: "–", cpu: "–"), agents: nil, pressure: .normal, summary: "Measuring…")

    private init(app: Figures, agents: Figures?, pressure: MemoryPressure, summary: String) {
        self.app = app
        self.agents = agents
        self.pressure = pressure
        self.summary = summary
    }

    init(_ snapshot: ResourceSnapshot, physicalMemory: UInt64 = ProcessInfo.processInfo.physicalMemory) {
        let app = snapshot.group(.app)
        let others = snapshot.groups.filter { $0.kind != .app }
        let appMemory = app?.memory ?? 0
        let othersMemory = others.reduce(0) { $0 + $1.memory }
        let othersCPU = ProcessCPUUsage.total(others.map(\.cpu))
        self.app = Figures(memory: DSFormat.memory(appMemory), cpu: DSFormat.cpu(app?.cpu ?? 0))
        agents =
            others.isEmpty ? nil : Figures(memory: DSFormat.memory(othersMemory), cpu: DSFormat.cpu(othersCPU))

        let share = Double(snapshot.memory) / Double(max(physicalMemory, 1))
        pressure = share >= 0.5 ? .critical : share >= 0.25 ? .high : .normal

        var summary = "Native itself uses \(self.app.memory) of memory and \(self.app.cpu) CPU."
        if let agents {
            summary +=
                " Its agents, with the tools they run and anything else Native started, use \(agents.memory) and \(agents.cpu) CPU."
        }
        let total = Int(clamping: snapshot.memory)
        summary +=
            " Together that's \(DSFormat.share(total, of: Int(clamping: physicalMemory))) of this Mac's \(DSFormat.memory(physicalMemory))."
        summary += " CPU percentages are shares of this Mac's total CPU capacity."
        self.summary = summary
    }
}
