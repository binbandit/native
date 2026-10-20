import SwiftUI

/// What other features know about a task that the sidebar asks about: for its filters, whether its
/// checkout has uncommitted changes and whether its branch has a pull request; for its row, what
/// can be done with that pull request. The app wires it from the Git and GitHub features; without
/// them every answer is no.
struct SidebarTaskInsights {
    var hasUncommittedChanges: @MainActor (SessionSummary) -> Bool = { _ in false }
    var hasPullRequest: @MainActor (SessionSummary) -> Bool = { _ in false }
    /// The row's "Pull Request" submenu, while the task's branch has one.
    var pullRequestMenu: @MainActor (SessionSummary) -> SidebarTaskMenu? = { _ in nil }
    /// Looks the answers up for tasks nobody has asked about yet (rows a filter hides never load
    /// their checkout), so turning a filter on finds them.
    var prepare: @MainActor ([SessionSummary]) async -> Void = { _ in }
}

extension EnvironmentValues {
    @Entry var sidebarTaskInsights = SidebarTaskInsights()
}
