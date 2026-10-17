import Foundation

/// Rate-limit budgets from `gh api rate_limit`, which itself costs nothing.
public struct RateLimit: Sendable, Hashable, Decodable {
    public struct Budget: Sendable, Hashable, Decodable {
        public var limit: Int
        public var remaining: Int
        public var resetsAt: Date

        public init(limit: Int, remaining: Int, resetsAt: Date) {
            self.limit = limit
            self.remaining = remaining
            self.resetsAt = resetsAt
        }

        private enum CodingKeys: String, CodingKey {
            case limit, remaining, reset
        }

        public init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            limit = try container.decode(Int.self, forKey: .limit)
            remaining = try container.decode(Int.self, forKey: .remaining)
            // Seconds since 1970 here, unlike the ISO dates everywhere else.
            resetsAt = Date(timeIntervalSince1970: try container.decode(Double.self, forKey: .reset))
        }
    }

    /// REST calls.
    public var core: Budget
    /// `gh search`, which has its own small budget of 30 a minute.
    public var search: Budget
    /// GraphQL points, which most `gh pr` commands spend.
    public var graphql: Budget

    public init(core: Budget, search: Budget, graphql: Budget) {
        self.core = core
        self.search = search
        self.graphql = graphql
    }

    private struct Resources: Decodable {
        var core: Budget
        var search: Budget
        var graphql: Budget
    }

    private enum CodingKeys: String, CodingKey {
        case resources
    }

    public init(from decoder: any Decoder) throws {
        let resources = try decoder.container(keyedBy: CodingKeys.self).decode(Resources.self, forKey: .resources)
        self.init(core: resources.core, search: resources.search, graphql: resources.graphql)
    }

    /// When every exhausted budget has refilled; `nil` when none is exhausted.
    public var exhaustedUntil: Date? {
        [core, search, graphql].filter { $0.remaining == 0 }.map(\.resetsAt).max()
    }
}
