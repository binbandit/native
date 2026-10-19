import Foundation
import Observation
import os

/// Each project's sidebar list, built once and kept until something it was built from changes:
/// the listing, archives, deletions, pins, the user's order, or an open session's last activity.
/// Streamed transcript updates touch none of those, so they don't rebuild (or re-sort) the list.
@Observable
final class ProjectSessionLists {
    @ObservationIgnored private var lists: [Project.ID: [SessionSummary]] = [:]
    /// Bumped whenever a kept list goes stale, so views showing one read it again.
    private var generation = 0

    /// The kept list for `project`, or a fresh one from `build`, kept until something `build`
    /// read changes.
    ///
    /// Read it from SwiftUI or `Observations`, never from a `withObservationTracking` that re-arms
    /// in its `onChange`: one change reaches that reader twice (through `generation`, bumped in the
    /// changed property's willSet, and through the property itself), so its observers double with
    /// every change. Keep Awake did that, and grew to gigabytes after about 25 tasks.
    func list(for project: Project.ID, build: () -> [SessionSummary]) -> [SessionSummary] {
        _ = generation
        if let list = lists[project] {
            return list
        }
        let list = withObservationTracking(build) { [weak self] in
            // Runs in the changing property's willSet, which the main actor makes.
            MainActor.assumeIsolated { self?.invalidate(project) }
        }
        AppModel.logger.debug("Built the session list for a project: \(list.count) sessions")
        lists[project] = list
        return list
    }

    private func invalidate(_ project: Project.ID) {
        lists[project] = nil
        generation += 1
    }
}
