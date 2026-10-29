/// The starting value and its receipt. An unavailable explicit choice keeps the agent's default,
/// matching ACP's new-task behavior; it must not silently select another saved preference.
public struct TaskDefaultResolution: Equatable, Sendable {
    public enum Source: String, Equatable, Sendable {
        case organization, project, user, lastUsed, agent
    }

    public let value: String?
    public let source: Source
    public let requested: String?
    public let unavailable: Bool
    public let restricted: Bool

    public init(
        offered: [String], agent: String?, user: String? = nil, project: String? = nil,
        lastUsed: String? = nil, forbidden: Set<String> = []
    ) {
        let candidates: [(String?, Source)] = [(project, .project), (user, .user), (lastUsed, .lastUsed)]
        let selected = candidates.first { $0.0?.isEmpty == false }
        requested = selected?.0
        unavailable = requested.map { !offered.contains($0) } ?? false
        let rejected = requested.map(forbidden.contains) ?? false
        let accepted = requested != nil && !unavailable && !rejected
        let initial = accepted ? requested : agent
        restricted = rejected || initial.map(forbidden.contains) == true
        if let initial, forbidden.contains(initial) {
            value = offered.first { !forbidden.contains($0) }
        } else {
            value = initial
        }
        source = restricted ? .organization : accepted ? selected?.1 ?? .agent : .agent
    }
}
