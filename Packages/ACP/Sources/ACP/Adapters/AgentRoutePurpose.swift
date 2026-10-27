import Foundation

public enum AgentRoutePurpose: String, CaseIterable, Codable, Hashable, Sendable {
    case conversation, title, commit, pullRequest, workflow, recovery
}
