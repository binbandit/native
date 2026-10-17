import Foundation

/// A provider's subscription rate limit, as Claude Code reports it in a `usage_update`'s
/// `_meta["_claude/rateLimit"]` whenever it changes (the Agent SDK's `SDKRateLimitInfo`).
public struct RateLimitInfo: Hashable, Sendable {
    public enum Status: Hashable, Sendable {
        case allowed
        /// Allowed, but close to the limit.
        case allowedWarning
        case rejected
        case other(String)

        public init(rawValue: String) {
            self = switch rawValue {
            case "allowed": .allowed
            case "allowed_warning": .allowedWarning
            case "rejected": .rejected
            default: .other(rawValue)
            }
        }
    }

    /// Which limit the status is about.
    public enum Window: Hashable, Sendable {
        /// The rolling five-hour session limit.
        case fiveHour
        case sevenDay
        case sevenDayOpus
        case sevenDaySonnet
        case sevenDayOverageIncluded
        /// Usage credits past the plan's limits.
        case overage
        case other(String)

        public init(rawValue: String) {
            self = switch rawValue {
            case "five_hour": .fiveHour
            case "seven_day": .sevenDay
            case "seven_day_opus": .sevenDayOpus
            case "seven_day_sonnet": .sevenDaySonnet
            case "seven_day_overage_included": .sevenDayOverageIncluded
            case "overage": .overage
            default: .other(rawValue)
            }
        }

        public var rawValue: String {
            switch self {
            case .fiveHour: "five_hour"
            case .sevenDay: "seven_day"
            case .sevenDayOpus: "seven_day_opus"
            case .sevenDaySonnet: "seven_day_sonnet"
            case .sevenDayOverageIncluded: "seven_day_overage_included"
            case .overage: "overage"
            case .other(let value): value
            }
        }
    }

    public var status: Status
    public var resetsAt: Date?
    public var window: Window?
    /// Used share of the window, 0-1.
    public var utilization: Double?
    public var overageStatus: Status?
    public var overageResetsAt: Date?
    /// Requests are drawing on usage credits past the plan's limit.
    public var isUsingOverage: Bool
    /// Why credits can't take over, such as `out_of_credits` or `overage_not_provisioned`.
    public var overageDisabledReason: String?

    public init(
        status: Status, resetsAt: Date? = nil, window: Window? = nil, utilization: Double? = nil,
        overageStatus: Status? = nil, overageResetsAt: Date? = nil, isUsingOverage: Bool = false,
        overageDisabledReason: String? = nil
    ) {
        self.status = status
        self.resetsAt = resetsAt
        self.window = window
        self.utilization = utilization
        self.overageStatus = overageStatus
        self.overageResetsAt = overageResetsAt
        self.isUsingOverage = isUsingOverage
        self.overageDisabledReason = overageDisabledReason
    }

    /// The status that decides whether requests go through. While credits cover the overflow the
    /// plan's own limit doesn't block, so the credits' status counts instead, as Claude Code reads it.
    public var effectiveStatus: Status {
        isUsingOverage ? (overageStatus ?? .allowed) : status
    }

    /// Whether the provider is refusing requests.
    public var isBlocking: Bool { effectiveStatus == .rejected }

    /// Whether the provider is close to refusing requests.
    public var isWarning: Bool { effectiveStatus == .allowedWarning }

    /// When requests go through again. With credits exhausted too, the earlier reset frees the user.
    public var blockedUntil: Date? {
        guard isBlocking else { return nil }
        if overageStatus == .rejected, let overageResetsAt {
            return resetsAt.map { min($0, overageResetsAt) } ?? overageResetsAt
        }
        return resetsAt ?? overageResetsAt
    }
}

extension RateLimitInfo: Decodable {
    private enum CodingKeys: String, CodingKey {
        case status, resetsAt, rateLimitType, utilization, overageStatus, overageResetsAt, isUsingOverage, overageDisabledReason
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        status = Status(rawValue: try container.decode(String.self, forKey: .status))
        // The extras are read leniently: an odd value shouldn't cost the status.
        resetsAt = container.lenient(Double.self, .resetsAt).map(Date.init(timeIntervalSince1970:))
        window = container.lenient(String.self, .rateLimitType).map(Window.init(rawValue:))
        utilization = container.lenient(Double.self, .utilization)
        overageStatus = container.lenient(String.self, .overageStatus).map(Status.init(rawValue:))
        overageResetsAt = container.lenient(Double.self, .overageResetsAt).map(Date.init(timeIntervalSince1970:))
        isUsingOverage = container.lenient(Bool.self, .isUsingOverage) ?? false
        overageDisabledReason = container.lenient(String.self, .overageDisabledReason)
    }
}

extension RateLimitInfo.Window: Codable {
    public init(from decoder: any Decoder) throws {
        self.init(rawValue: try decoder.singleValueContainer().decode(String.self))
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

/// The adapter extras a `usage_update` carries in `_meta` that Native reads. Absent or odd fields
/// decode as nil, never failing the usage update, and an empty `_meta` equals a missing one.
public struct UsageMeta: Decodable, Hashable, Sendable {
    /// Claude Code's rate-limit status, sent when it changes.
    public var rateLimit: RateLimitInfo?

    private enum CodingKeys: String, CodingKey {
        case rateLimit = "_claude/rateLimit"
    }

    public init(rateLimit: RateLimitInfo? = nil) {
        self.rateLimit = rateLimit
    }

    public init(from decoder: any Decoder) throws {
        rateLimit = try decoder.container(keyedBy: CodingKeys.self).lenient(RateLimitInfo.self, .rateLimit)
    }
}

extension KeyedDecodingContainer {
    /// Lets a synthesized `Decodable` hold a non-optional `UsageMeta` (`var _meta = UsageMeta()`) that
    /// tolerates a missing or malformed `_meta`.
    func decode(_ type: UsageMeta.Type, forKey key: Key) throws -> UsageMeta {
        lenient(UsageMeta.self, key) ?? UsageMeta()
    }

    fileprivate func lenient<Value: Decodable>(_ type: Value.Type, _ key: Key) -> Value? {
        (try? decodeIfPresent(type, forKey: key)).flatMap(\.self)
    }
}
