/// Every store Native keeps or knows about, with one entry per `DataStoreID`. It is data, not
/// discovery: building or reading it never looks at the disk, and the stores it lists outside
/// Native are described so a plan can say what it can't reach, never so Native can read them.
/// docs/enterprise/data-lifecycle.md renders the same table (`markdownTable`).
public struct DataStoreInventory: Sendable {
    public let entries: [DataStoreEntry]
    private let index: [DataStoreID: Int]

    init(_ entries: [DataStoreEntry]) {
        self.entries = entries
        var index: [DataStoreID: Int] = [:]
        for (offset, entry) in entries.enumerated() where index[entry.id] == nil {
            index[entry.id] = offset
        }
        self.index = index
    }

    public func entry(_ id: DataStoreID) -> DataStoreEntry? {
        index[id].map { entries[$0] }
    }

    /// Native's stores, as the source at this revision writes them.
    public static let native = DataStoreInventory(
        hostEntries + appEntries + artifactEntries + resourceEntries + outsideEntries)

    /// What's wrong with the inventory itself; empty for `native`.
    var problems: [String] {
        var problems: [String] = []
        let ids = entries.map(\.id)
        for id in Set(ids) where ids.count(where: { $0 == id }) > 1 {
            problems.append("\(id.rawValue) is listed more than once")
        }
        for entry in entries {
            let name = entry.id.rawValue
            if entry.copies.isEmpty { problems.append("\(name) has no copies") }
            for case .file(let root, let template) in entry.copies.map(\.location) {
                if !root.isFileBacked { problems.append("\(name) has a file copy under \(root.rawValue)") }
                if template.isEmpty || template.contains(where: { !DataPathPattern.isPlainComponent($0) }) {
                    problems.append("\(name) has a path template that could leave its root")
                }
            }
            if entry.ownership == .native, entry.owners.isEmpty { problems.append("\(name) names no owner") }
            if entry.support.delete == .adapterPending, entry.followUp == nil {
                problems.append("\(name) waits for an adapter no job builds")
            }
            if entry.ownership != .native, entry.support.delete == .adapterPending, entry.followUp != .externalAgents {
                problems.append("\(name) isn't Native's, so only an explicit external adapter could delete it")
            }
            for source in entry.reimportedFrom where self.entry(source) == nil {
                problems.append("\(name) is reimported from \(source.rawValue), which isn't listed")
            }
        }
        return problems
    }
}
