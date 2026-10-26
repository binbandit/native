import Foundation

/// Version 1 records only approvals observed through ACP. Identifiers for requests, actions and
/// options are host-generated UUIDs, never arbitrary agent strings. No conversation content lives here.
public struct HostApprovalAuditRecord: Codable, Hashable, Sendable {
    public enum PolicyMode: String, Codable, Sendable {
        case ordinary, restricted, blocked, unknown
    }

    public enum State: String, Codable, Sendable {
        case requested, decided, withdrawn
        case deliveryAccepted, deliveryFailed
    }

    public enum OptionKind: String, Codable, Sendable {
        case allowOnce = "allow_once"
        case allowAlways = "allow_always"
        case rejectOnce = "reject_once"
        case rejectAlways = "reject_always"
        case unknown
    }

    public struct Option: Codable, Hashable, Sendable {
        public var id: UUID
        public var kind: OptionKind

        public init(id: UUID = UUID(), kind: OptionKind) {
            self.id = id
            self.kind = kind
        }
    }

    public enum Source: String, Codable, Sendable {
        case agent, direct, notification, host
    }

    public enum Reason: String, Codable, Sendable {
        case cancelled, requestEnded, hostRestarted, transportUnavailable, transportWriteFailed
    }

    public var schemaVersion: Int = 1
    public var sequence: Int64 = 0
    public var hostID: HostID
    public var sessionID: HostSessionID
    public var requestID: UUID
    public var actionID: UUID
    public var state: State
    public var options: [Option] = []
    public var selectedOptionID: UUID?
    public var actor: HostClientIdentity
    public var source: Source
    /// The existing managed policy revision, or nil when unavailable/unmanaged.
    public var policyRevision: String?
    public var policyMode: PolicyMode
    public var wallTime: Date
    /// Monotonic time is comparable only within this host process epoch. Sequence orders all epochs.
    public var epoch: UUID
    public var uptimeNanoseconds: UInt64
    public var reason: Reason?

    public init(
        hostID: HostID, sessionID: HostSessionID, requestID: UUID = UUID(), actionID: UUID = UUID(),
        state: State, selectedOptionID: UUID? = nil, actor: HostClientIdentity = .unknown, source: Source,
        policyRevision: String?, policyMode: PolicyMode, epoch: UUID, reason: Reason? = nil
    ) {
        self.hostID = hostID
        self.sessionID = sessionID
        self.requestID = requestID
        self.actionID = actionID
        self.state = state
        self.selectedOptionID = selectedOptionID
        self.actor = actor
        self.source = source
        self.policyRevision = policyRevision
        self.policyMode = policyMode
        wallTime = .now
        self.epoch = epoch
        uptimeNanoseconds = DispatchTime.now().uptimeNanoseconds
        self.reason = reason
    }
}

public struct HostApprovalAuditCursor: Codable, Hashable, Sendable {
    public var hostID: HostID
    public var sequence: Int64

    public init(hostID: HostID, sequence: Int64) {
        self.hostID = hostID
        self.sequence = sequence
    }
}

/// A bounded local JSONL page. A gap or invalid record is explicit, never silently skipped.
public struct HostApprovalAuditPage: Codable, Sendable {
    public enum Status: String, Codable, Sendable {
        case available, missingRange, invalidCursor, unavailable
    }

    public struct MissingRange: Codable, Sendable {
        public var first: Int64
        public var last: Int64

        public init(first: Int64, last: Int64) {
            self.first = first
            self.last = last
        }
    }

    public var status: Status
    public var jsonl: String
    public var cursor: HostApprovalAuditCursor
    public var highWater: Int64
    public var hasMore: Bool
    public var missingRange: MissingRange?

    public init(
        status: Status, jsonl: String = "", cursor: HostApprovalAuditCursor, highWater: Int64 = 0,
        hasMore: Bool = false, missingRange: MissingRange? = nil
    ) {
        self.status = status
        self.jsonl = jsonl
        self.cursor = cursor
        self.highWater = highWater
        self.hasMore = hasMore
        self.missingRange = missingRange
    }
}
