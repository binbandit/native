import Foundation

/// The projects whose sessions are hidden in the sidebar, remembered across launches with
/// `@AppStorage`. Projects start expanded.
struct CollapsedProjects: RawRepresentable, Equatable {
    static let storageKey = "sidebar.collapsedProjects"

    private(set) var ids: Set<Project.ID>

    init(_ ids: Set<Project.ID> = []) {
        self.ids = ids
    }

    init?(rawValue: String) {
        ids = Set(rawValue.split(separator: ",").compactMap { UUID(uuidString: String($0)) })
    }

    var rawValue: String {
        ids.map(\.uuidString).sorted().joined(separator: ",")
    }

    func contains(_ id: Project.ID) -> Bool {
        ids.contains(id)
    }

    mutating func set(_ id: Project.ID, collapsed: Bool) {
        if collapsed {
            ids.insert(id)
        } else {
            ids.remove(id)
        }
    }
}
