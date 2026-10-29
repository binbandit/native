import SwiftUI

extension EnvironmentValues {
    @Entry var projectDisplayName = ProjectDisplayNameResolver()
}

/// Features holding folder URLs share the sidebar's naming without owning the project store.
/// A stable environment value lets observation track the store reads at the point of use.
struct ProjectDisplayNameResolver: Equatable {
    var projects: Projects?

    nonisolated static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.projects === rhs.projects
    }

    func callAsFunction(_ url: URL) -> String {
        projects?.name(for: url) ?? url.lastPathComponent
    }
}
