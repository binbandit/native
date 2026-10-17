import Foundation
import NativeAutomation

/// The lead's session and what it's doing in it. The lead works in one session for the whole
/// expedition, so it remembers the objective, the route and every revision.
public nonisolated struct LeadRun: Codable, Hashable, Sendable {
    public enum Job: Codable, Hashable, Sendable {
        /// Drafting the first route.
        case planning
        /// Revising the route with the user's feedback.
        case revising
        /// Looking at the legs ahead after `leg`'s checkpoint passed.
        case reviewingLeg(String)
        /// Writing the debrief.
        case debriefing
        /// Answering the user, outside any job.
        case conversation
    }

    public var job: Job = .planning
    public var status: WorkflowStepStatus = .waiting
    public var task: UUID?
    /// Route replies in a row that didn't parse. The lead gets the problem back twice, then the
    /// user decides.
    public var unreadRoutes = 0
    public var latestReply: String?
    public var sessionCost: Double?
    public var waitingSince: Date?

    public init() {}
}
