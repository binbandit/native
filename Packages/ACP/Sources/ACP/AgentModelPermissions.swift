/// Translates the permission choices reported by an ACP session, independent of agent identity.
public enum AgentModelPermissions {
    public enum Reason: String, Codable, Sendable {
        case equivalent, stricter, safestAvailable, unknown
    }

    public struct Selection: Equatable, Sendable {
        public let value: String
        public let reason: Reason
    }

    /// Known semantics outrank an unfamiliar spelling. For wholly unfamiliar lists, the first
    /// advertised permission level is the only available fallback; callers must disclose that
    /// its safety could not be compared. Matching unknown IDs across agents proves nothing.
    public static func selection(
        for source: String?, offered: [String], forbidden: Set<String> = []
    ) -> Selection? {
        let allowed = offered.filter { !forbidden.contains($0) }
        guard let first = allowed.first else { return nil }
        let ranked = allowed.compactMap { value in level(value).map { (value: value, level: $0) } }
        let safest = ranked.min { $0.level.rank < $1.level.rank }?.value ?? first
        guard let source, let wanted = level(source) else {
            return Selection(value: safest, reason: .unknown)
        }
        if allowed.contains(source) {
            return Selection(value: source, reason: .equivalent)
        }
        if wanted == .refuses {
            return Selection(value: safest, reason: .unknown)
        }
        if let equal = ranked.first(where: { $0.level == wanted }) {
            return Selection(value: equal.value, reason: .equivalent)
        }
        if let stricter = ranked.filter({ $0.level.isSafer(than: wanted) }).max(by: { $0.level.rank < $1.level.rank }) {
            return Selection(value: stricter.value, reason: .stricter)
        }
        return Selection(value: safest, reason: ranked.count == allowed.count ? .safestAvailable : .unknown)
    }

    public static func replacement(for source: String, offered: [String], forbidden: Set<String> = []) -> String? {
        selection(for: source, offered: offered, forbidden: forbidden)?.value
    }

    /// A documented level that protects changes with approval or a read-only restriction.
    /// Unknown values and levels granting automatic changes cannot justify hiding a notice.
    public static func isConservative(_ value: String) -> Bool {
        switch level(value) {
        case .asks, .readOnly, .planning: true
        default: false
        }
    }

    private enum Level {
        case asks, edits, workspace, review, full, refuses, planning, readOnly

        var rank: Int {
            switch self {
            case .planning, .readOnly: -1
            case .asks, .refuses: 0
            case .edits, .workspace: 1
            case .review: 2
            case .full: 3
            }
        }

        func isSafer(than other: Level) -> Bool {
            // Trusted edits, a workspace boundary and risk review grant different actions.
            // Only asking/refusing every change is known safer across those grants. Full
            // access can narrow to any of them.
            if other == .planning || other == .readOnly {
                return self != other && (self == .planning || self == .readOnly)
            }
            return self != other && (rank < 0 || self == .asks || self == .refuses || other == .full)
        }
    }

    private static func level(_ value: String) -> Level? {
        switch value {
        case "default": .asks
        case "read-only": .readOnly
        case "plan": .planning
        case "dontAsk": .refuses
        case "acceptEdits": .edits
        case "workspace-write": .workspace
        case "auto", "agent": .review
        case "bypassPermissions", "agent-full-access": .full
        default: nil
        }
    }
}
