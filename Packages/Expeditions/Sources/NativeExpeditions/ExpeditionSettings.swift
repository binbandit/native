import Foundation

/// How an expedition runs, chosen when it starts.
public nonisolated struct ExpeditionSettings: Codable, Hashable, Sendable {
    /// Review rounds a checkpoint gets before it waits on the user.
    public var fixRounds: Int
    /// Turns each assignment's goal may take.
    public var assignmentIterations: Int
    /// Assignments that may run at once. They share the base, so more than one can collide.
    public var maxParallel: Int
    /// Ask the lead to revise the legs ahead after each checkpoint passes.
    public var consultsLeadBetweenLegs: Bool
    public var opensPullRequest: Bool
    public var draftPullRequest: Bool

    public init(
        fixRounds: Int = 2, assignmentIterations: Int = 15, maxParallel: Int = 1, consultsLeadBetweenLegs: Bool = true,
        opensPullRequest: Bool = true, draftPullRequest: Bool = false
    ) {
        self.fixRounds = max(1, fixRounds)
        self.assignmentIterations = max(1, assignmentIterations)
        self.maxParallel = max(1, maxParallel)
        self.consultsLeadBetweenLegs = consultsLeadBetweenLegs
        self.opensPullRequest = opensPullRequest
        self.draftPullRequest = draftPullRequest
    }
}
