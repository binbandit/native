/// How the resource table orders its process trees: most first by the chosen column, or as found
/// (Native, then each agent). Processes within a tree keep their tree order.
enum ResourceSort: CaseIterable {
    case name, cpu, memory

    var title: String {
        switch self {
        case .name: "Name"
        case .cpu: "CPU"
        case .memory: "Memory"
        }
    }

    func ordered(_ groups: [ProcessGroup]) -> [ProcessGroup] {
        switch self {
        case .name: groups
        case .cpu: groups.sorted { $0.cpu > $1.cpu }
        case .memory: groups.sorted { $0.memory > $1.memory }
        }
    }
}
