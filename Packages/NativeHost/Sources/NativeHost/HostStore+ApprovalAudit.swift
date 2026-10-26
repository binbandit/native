import Foundation
import NativeHostProtocol

extension HostStore {
    static let approvalAuditTables = """
        ALTER TABLE approvals ADD COLUMN audit_request_id TEXT;
        ALTER TABLE approvals ADD COLUMN audit_options TEXT;
        ALTER TABLE approvals ADD COLUMN audit_decided INTEGER NOT NULL DEFAULT 0;
        CREATE TABLE approval_audit (sequence INTEGER PRIMARY KEY, record TEXT NOT NULL);
        CREATE TABLE approval_audit_heads (
            request_id TEXT PRIMARY KEY, record TEXT NOT NULL, delivery_pending INTEGER NOT NULL
        );
        """

    /// Content-bearing option ids stay in the pre-existing pending-approval table, never in audit.
    private struct ApprovalOption: Codable {
        let wireID: String
        let auditID: UUID
    }

    func requestApprovalAudit(
        _ value: HostApprovalAuditRecord, toolCallID: String, title: String?, optionIDs: [String],
        optionKinds: [HostApprovalAuditRecord.OptionKind] = []
    ) throws {
        guard optionIDs.count <= 64, Set(optionIDs).count == optionIDs.count else {
            throw ApprovalAuditFailure.invalidOption
        }
        var record = value
        record.options = optionIDs.indices.map { index in
            .init(kind: index < optionKinds.count ? optionKinds[index] : .unknown)
        }
        let bindings = zip(optionIDs, record.options).map { ApprovalOption(wireID: $0, auditID: $1.id) }
        try transaction {
            // Never overwrite a still-waiting request with the same tool id.
            guard
                try database.query(
                    "SELECT 1 FROM approvals WHERE session_id = ? AND tool_call_id = ?",
                    .text(record.sessionID.description), .text(toolCallID)
                ).isEmpty
            else { throw ApprovalAuditFailure.notPending }
            try appendApprovalAudit(record, deliveryPending: false)
            try database.run(
                """
                INSERT INTO approvals (session_id, tool_call_id, title, requested_at, audit_request_id, audit_options)
                VALUES (?, ?, ?, ?, ?, ?)
                """,
                .text(record.sessionID.description), .text(toolCallID), .text(title), .date(record.wallTime),
                .text(record.requestID.uuidString),
                try JSONColumn.encode(bindings))
        }
    }

    /// Transitioning the pending row and committing the decision are a single durable first-wins claim.
    func decideApprovalAudit(
        sessionID: HostSessionID, toolCallID: String, optionID: String?, actor: HostClientIdentity,
        source: HostApprovalAuditRecord.Source, policy: HostPolicy, epoch: UUID
    ) throws -> HostApprovalAuditRecord {
        try transaction {
            guard
                let row = try database.query(
                    "SELECT audit_request_id, audit_options FROM approvals WHERE session_id = ? AND tool_call_id = ? AND audit_decided = 0",
                    .text(sessionID.description), .text(toolCallID)
                ).first,
                let requestID = row[0].text,
                var record = try approvalAuditHead(requestID)
            else { throw ApprovalAuditFailure.notPending }
            var selected: UUID?
            if let optionID {
                guard let text = row[1].text,
                    let option = try JSONDecoder().decode([ApprovalOption].self, from: Data(text.utf8))
                        .first(where: { $0.wireID == optionID })
                else { throw ApprovalAuditFailure.invalidOption }
                selected = option.auditID
            }
            record.state = optionID == nil ? .withdrawn : .decided
            record.selectedOptionID = selected
            record.actor = actor
            record.source = source
            record.reason = optionID == nil ? .cancelled : nil
            stampApprovalAudit(&record, policy: policy, epoch: epoch)
            try appendApprovalAudit(record, deliveryPending: true)
            // Retain only the action key so a reused tool id cannot receive a second decision.
            try database.run(
                """
                UPDATE approvals SET audit_decided = 1, title = NULL, audit_options = NULL
                WHERE session_id = ? AND tool_call_id = ?
                """, .text(sessionID.description), .text(toolCallID))
            return record
        }
    }

    func finishApprovalDelivery(
        _ decision: HostApprovalAuditRecord, failure: HostApprovalAuditRecord.Reason?, policy: HostPolicy, epoch: UUID
    ) throws {
        try transaction {
            var record = decision
            record.state = failure == nil ? .deliveryAccepted : .deliveryFailed
            record.reason = failure
            stampApprovalAudit(&record, policy: policy, epoch: epoch)
            try appendApprovalAudit(record, deliveryPending: false)
        }
    }

    func withdrawApprovalAudit(
        sessionID: HostSessionID, toolCallID: String, policy: HostPolicy, epoch: UUID
    ) throws {
        try transaction {
            guard
                let id = try database.query(
                    "SELECT audit_request_id FROM approvals WHERE session_id = ? AND tool_call_id = ? AND audit_decided = 0",
                    .text(sessionID.description), .text(toolCallID)
                ).first?.first?.text,
                var record = try approvalAuditHead(id)
            else { return }
            record.state = .withdrawn
            record.reason = .requestEnded
            record.actor = .unknown
            record.source = .host
            stampApprovalAudit(&record, policy: policy, epoch: epoch)
            try appendApprovalAudit(record, deliveryPending: false)
            try removeApproval(sessionID: sessionID, toolCallID: toolCallID)
        }
    }

    /// Runs before clients or agents are admitted after restart. Never resends a previous decision.
    func recoverApprovalAudit(policy: HostPolicy, epoch: UUID) throws {
        try transaction {
            for row in try database.query("SELECT record, delivery_pending FROM approval_audit_heads") {
                guard let text = row[0].text else { throw ApprovalAuditFailure.unavailable }
                var record = try JSONDecoder().decode(HostApprovalAuditRecord.self, from: Data(text.utf8))
                if row[1].bool {
                    // The response may already have reached the agent. Its execution is unknown.
                    record.state = .deliveryFailed
                } else if record.state == .requested {
                    record.state = .withdrawn
                    record.actor = .unknown
                    record.source = .host
                } else {
                    continue
                }
                record.reason = .hostRestarted
                stampApprovalAudit(&record, policy: policy, epoch: epoch)
                try appendApprovalAudit(record, deliveryPending: false)
            }
            // Includes legacy approvals, for which provenance is unavailable. No invented audit events.
            try database.run("DELETE FROM approvals WHERE audit_decided = 0")
        }
    }

    func exportApprovalAudit(_ params: ExportApprovalAuditParams, hostID: HostID) -> HostApprovalAuditPage {
        let cursor = params.cursor ?? HostApprovalAuditCursor(hostID: hostID, sequence: 0)
        do {
            let high = try approvalAuditSequence()
            guard cursor.hostID == hostID, cursor.sequence >= 0, cursor.sequence <= high else {
                return HostApprovalAuditPage(status: .invalidCursor, cursor: cursor, highWater: high)
            }
            let rows = try database.query(
                "SELECT sequence, record FROM approval_audit WHERE sequence > ? ORDER BY sequence LIMIT ?",
                .integer(cursor.sequence), .integer(Int64(min(max(params.limit, 1), 200))))
            var expected = cursor.sequence
            var jsonl = ""
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]
            encoder.dateEncodingStrategy = .iso8601
            for row in rows {
                guard let seq = row[0].integer, let text = row[1].text else {
                    throw ApprovalAuditFailure.unavailable
                }
                guard seq == expected + 1 else {
                    return HostApprovalAuditPage(
                        status: .missingRange, cursor: cursor, highWater: high,
                        missingRange: .init(first: expected + 1, last: seq - 1))
                }
                let record = try JSONDecoder().decode(HostApprovalAuditRecord.self, from: Data(text.utf8))
                guard record.schemaVersion == 1, record.sequence == seq, record.hostID == hostID else {
                    throw ApprovalAuditFailure.unavailable
                }
                let line = String(decoding: try encoder.encode(record), as: UTF8.self) + "\n"
                guard line.utf8.count <= 256 * 1024 else { throw ApprovalAuditFailure.unavailable }
                if jsonl.utf8.count + line.utf8.count > 256 * 1024 {
                    return HostApprovalAuditPage(
                        status: .available, jsonl: jsonl, cursor: .init(hostID: hostID, sequence: expected),
                        highWater: high, hasMore: true)
                }
                jsonl += line
                expected = seq
            }
            if rows.count < min(max(params.limit, 1), 200), expected < high {
                return HostApprovalAuditPage(
                    status: .missingRange, cursor: cursor, highWater: high,
                    missingRange: .init(first: expected + 1, last: high))
            }
            return HostApprovalAuditPage(
                status: .available, jsonl: jsonl, cursor: .init(hostID: hostID, sequence: expected),
                highWater: high, hasMore: expected < high)
        } catch {
            // SQLite and decoding errors may carry values. Only a fixed typed status crosses RPC.
            return HostApprovalAuditPage(status: .unavailable, cursor: cursor)
        }
    }

    private func approvalAuditHead(_ requestID: String) throws -> HostApprovalAuditRecord? {
        try database.query("SELECT record FROM approval_audit_heads WHERE request_id = ?", .text(requestID))
            .first?.first?.text.map { try JSONDecoder().decode(HostApprovalAuditRecord.self, from: Data($0.utf8)) }
    }

    private func approvalAuditSequence() throws -> Int64 {
        guard let text = try meta("approval_audit_sequence") else { return 0 }
        guard let value = Int64(text), value >= 0, value < Int64.max else { throw ApprovalAuditFailure.unavailable }
        return value
    }

    /// Called only inside a transaction. The separate high water also exposes deleted trailing rows.
    private func appendApprovalAudit(_ value: HostApprovalAuditRecord, deliveryPending: Bool) throws {
        var record = value
        record.sequence = try approvalAuditSequence() + 1
        let json = try JSONColumn.encode(record)
        try database.run("INSERT INTO approval_audit (sequence, record) VALUES (?, ?)", .integer(record.sequence), json)
        try database.run(
            """
            INSERT INTO approval_audit_heads (request_id, record, delivery_pending) VALUES (?, ?, ?)
            ON CONFLICT(request_id) DO UPDATE SET record = excluded.record, delivery_pending = excluded.delivery_pending
            """, .text(record.requestID.uuidString), json, .bool(deliveryPending))
        try setMeta("approval_audit_sequence", String(record.sequence))
    }

    private func stampApprovalAudit(_ record: inout HostApprovalAuditRecord, policy: HostPolicy, epoch: UUID) {
        record.wallTime = .now
        record.epoch = epoch
        record.uptimeNanoseconds = DispatchTime.now().uptimeNanoseconds
        record.policyRevision = policy.revision
        record.policyMode = .init(rawValue: policy.mode.rawValue) ?? .unknown
    }
}

/// Fixed errors keep storage and arbitrary wire values out of approval RPC errors and logs.
enum ApprovalAuditFailure: Error, LocalizedError {
    case unavailable, notPending, invalidOption, deliveryUncertain

    var errorDescription: String? {
        switch self {
        case .unavailable: "The approval record could not be saved. The request remains unresolved."
        case .notPending: "This approval is no longer pending."
        case .invalidOption: "This option is not part of the pending approval."
        case .deliveryUncertain: "The decision was recorded, but delivery to the agent is uncertain. Do not retry it."
        }
    }
}
