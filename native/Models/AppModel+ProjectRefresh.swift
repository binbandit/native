import Foundation

extension AppModel {
    func refreshProject(_ id: Project.ID) async {
        guard let project = projects.project(id), let refreshProjectState,
            refreshingProjects.insert(id).inserted
        else { return }
        defer { refreshingProjects.remove(id) }
        let failures = await refreshProjectState(
            project,
            allSessions(in: id).filter {
                !pendingDeletionKeys.contains($0.id)
            })
        // Removing the project while it loads must not leave an orphaned failure.
        guard projects.project(id) != nil else { return }
        if failures.isEmpty {
            problems.resolve(.refresh, in: id)
        } else {
            problems.report(
                ProjectProblem(
                    project: id, work: .refresh, title: "Couldn't refresh task state",
                    recovery: "The last known state is still shown for tasks that couldn't refresh.",
                    suggestion: "Check the project folder, host connection and GitHub sign-in, then Retry.",
                    details: failures.joined(separator: "\n")))
        }
    }
}
