import Foundation
import Observation

/// The projects' problems (`ProjectProblem`) in the order they happened, and which ones are being
/// retried, so every client shows the same thing.
@Observable
final class ProjectProblems {
    private(set) var all: [ProjectProblem] = []
    private(set) var retrying: Set<ProjectProblem.ID> = []

    func problems(in project: Project.ID) -> [ProjectProblem] {
        all.filter { $0.project == project }
    }

    /// Records a failure, in place of an earlier failure of the same work.
    func report(_ problem: ProjectProblem) {
        if let index = all.firstIndex(where: { $0.id == problem.id }) {
            all[index] = problem
        } else {
            all.append(problem)
        }
    }

    /// Forgets a failure: its work succeeded, the user dismissed it, or it no longer matters.
    func resolve(_ id: ProjectProblem.ID) {
        all.removeAll { $0.id == id }
    }

    func resolve(_ work: ProjectProblem.Work, in project: Project.ID) {
        resolve(ProjectProblem.ID(project: project, work: work))
    }

    /// Forgets every failure that matches, as when its project or agent goes away.
    func resolveAll(where matches: (ProjectProblem) -> Bool) {
        all.removeAll(where: matches)
    }

    /// Marks a retry as under way, or returns false when one already is.
    func beginRetry(_ id: ProjectProblem.ID) -> Bool {
        retrying.insert(id).inserted
    }

    func endRetry(_ id: ProjectProblem.ID) {
        retrying.remove(id)
    }
}
