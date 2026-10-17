import Foundation

/// What's checked before an expedition sets out. Warnings come with the fix and never block,
/// except having no crew at all.
public nonisolated struct ExpeditionReadiness: Hashable, Sendable {
    public struct Warning: Hashable, Sendable, Identifiable {
        public var id: String
        public var message: String
        public var isBlocking: Bool

        public init(id: String, message: String, isBlocking: Bool = false) {
            self.id = id
            self.message = message
            self.isBlocking = isBlocking
        }
    }

    public var crew: Crew?
    /// Agents the user picked that can't start, with why and how to fix it.
    public var unavailableAgents: [String] = []
    /// Nil while it's still being checked.
    public var isRepository: Bool?
    public var hasUncommittedChanges = false
    public var usesWorktree = true
    public var budget: ExpeditionBudget = .unlimited
    public var opensPullRequest = true
    /// Whether `gh` is installed and signed in; nil while unknown.
    public var gitHubReady: Bool?

    public init() {}

    public var warnings: [Warning] {
        var warnings: [Warning] = []
        if crew == nil {
            warnings.append(
                Warning(
                    id: "crew",
                    message: "No agent is ready to take the crew. Install or sign in to one in Settings ▸ Agents.",
                    isBlocking: true))
        }
        warnings += unavailableAgents.map { Warning(id: "agent-\($0)", message: $0) }
        if usesWorktree, isRepository == false {
            warnings.append(
                Warning(
                    id: "git",
                    message:
                        "The project isn't a git repository, so the crew can't get a worktree of its own. It will work in the project folder.",
                    isBlocking: false))
        }
        if usesWorktree, hasUncommittedChanges {
            warnings.append(
                Warning(
                    id: "dirty",
                    message:
                        "The project has uncommitted changes. They won't be in the crew's worktree; commit them first if the crew needs them."
                ))
        }
        if let crew, crew.reviewerIsOnlyBuilder, crew.agents.count == 1 {
            warnings.append(
                Warning(
                    id: "reviewer",
                    message:
                        "\(crew.reviewer.name) reviews its own work. A second agent catches more; add one to the crew if you have it."
                ))
        }
        if budget.isUnlimited {
            warnings.append(
                Warning(
                    id: "budget",
                    message:
                        "There's no budget: the crew stops only when the work is done, or at each assignment's turn limit."
                ))
        }
        if opensPullRequest, gitHubReady == false {
            warnings.append(
                Warning(
                    id: "github",
                    message:
                        "The GitHub CLI isn't signed in, so the pull request at the end would fail. Run gh auth login, or leave the pull request off."
                ))
        }
        if opensPullRequest, isRepository == false {
            warnings.append(
                Warning(
                    id: "pull-request",
                    message:
                        "Without a git repository there's no pull request at the end; the debrief is still written."))
        }
        return warnings
    }

    public var canStart: Bool {
        !warnings.contains(where: \.isBlocking)
    }
}
