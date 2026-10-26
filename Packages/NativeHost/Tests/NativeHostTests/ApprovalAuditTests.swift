import ACP
import Foundation
import NativeHostClient
import NativeHostProtocol
import Testing

@testable import NativeHost

@Suite struct ApprovalAuditTests {
    static let canary = "PRIVATE_COMMAND_TOKEN_PATH_PROMPT_canary"
    static let firstActor = HostClientIdentity.pairedDevice(publicKey: Data(repeating: 7, count: 32))
    static let secondActor = HostClientIdentity.pairedDevice(publicKey: Data(repeating: 9, count: 32))

    @Test(arguments: ["transition", "append", "disk", "commit"])
    @HostActor func failedPendingTransitionSendsNoAnswer(_ failure: String) async throws {
        let rig = try PolicyRig(.unrestricted)
        let client = try await connect(rig)
        defer { rig.stop() }
        let (session, tool) = try await request(rig, client)
        switch failure {
        case "transition":
            try rig.core.store.database.execute(
                "CREATE TRIGGER fail_delete BEFORE UPDATE ON approvals BEGIN SELECT RAISE(ABORT, '\(Self.canary)'); END"
            )
        case "append":
            try rig.core.store.database.execute(
                "CREATE TRIGGER fail_append BEFORE INSERT ON approval_audit BEGIN SELECT RAISE(ABORT, '\(Self.canary)'); END"
            )
        case "commit":
            try rig.core.store.database.execute(
                """
                CREATE TABLE fail_parent (id INTEGER PRIMARY KEY);
                CREATE TABLE fail_child (id INTEGER REFERENCES fail_parent(id) DEFERRABLE INITIALLY DEFERRED);
                CREATE TRIGGER fail_commit AFTER INSERT ON approval_audit
                WHEN json_extract(NEW.record, '$.state') = 'decided'
                BEGIN INSERT INTO fail_child VALUES (1); END;
                """)
        default: try rig.core.store.database.execute("PRAGMA query_only = ON")
        }
        do {
            try await client.respondPermission(.init(sessionID: session, toolCallID: tool, optionID: "allow"))
            Issue.record("A failed transaction sent an answer")
        } catch {
            #expect(!error.localizedDescription.contains(Self.canary))
        }
        #expect(rig.core.sessions[session]?.pendingPermissions[tool] != nil)
        #expect(try records(rig.core.store).map(\.state) == [.requested])
        #expect(try rig.core.store.approvals()[session] == [tool])
        try await Task.sleep(for: .milliseconds(100))
        #expect(rig.core.sessions[session]?.mirror.state.pendingPermissions.count == 1)
        #expect(rig.core.sessions[session]?.turn != nil, "the fake agent is still waiting")
        try rig.core.store.database.execute("PRAGMA query_only = OFF")
        await client.stop()
    }

    @Test @HostActor func requestAppendFailureNeverForwardsAnApprovableEvent() async throws {
        let rig = try PolicyRig(.unrestricted)
        let client = try await connect(rig)
        defer { rig.stop() }
        try await client.syncAgents([rig.agentSpec()])
        let session = try await client.newSession(.init(agentID: "fake", cwd: rig.root.path()))
        try rig.core.store.database.execute(
            "CREATE TRIGGER fail_append BEFORE INSERT ON approval_audit BEGIN SELECT RAISE(ABORT, 'injected'); END")
        _ = try await client.prompt(.init(sessionID: session.id, text: "permission"))
        try await rig.waitUntil("prompt delivery") { rig.agentReceived.contains { $0.contains("permission") } }
        try await Task.sleep(for: .milliseconds(200))
        #expect(try records(rig.core.store).isEmpty)
        #expect(rig.core.sessions[session.id]?.mirror.state.pendingPermissions.isEmpty == true)
        #expect(rig.core.sessions[session.id]?.turn != nil)
        await client.stop()
    }

    @Test(arguments: [false, true])
    @HostActor func racingActorsAndDuplicatesAreFirstWins(_ notification: Bool) async throws {
        let policy = HostPolicy(
            mode: .ordinary, capabilities: Set(HostCapability.allCases), revision: "0123456789abcdef")
        let rig = try PolicyRig(policy)
        let first = try await connect(rig, identity: Self.firstActor)
        let second = try await connect(rig, identity: Self.secondActor)
        defer { rig.stop() }
        let (session, tool) = try await request(rig, first)
        let notice = try #require(try rig.core.store.activeNotifications().first { $0.kind == .permission })
        async let a = answer(first, session, tool, notice.id, notification, "allow")
        async let b = answer(second, session, tool, notice.id, notification, "reject")
        let winners = await [a, b]
        #expect(winners.filter { $0 }.count == 1)
        let rows = try records(rig.core.store)
        #expect(rows.map(\.state) == [.requested, .decided, .deliveryAccepted])
        #expect(rows[1].actor == (winners[0] ? Self.firstActor : Self.secondActor))
        #expect(rows[1].source == (notification ? .notification : .direct))
        #expect(rows[1].selectedOptionID != nil)
        #expect(rows.allSatisfy { $0.policyRevision == policy.revision })
        #expect(rows.allSatisfy { $0.requestID == rows[0].requestID && $0.actionID == rows[0].actionID })
        await #expect(throws: (any Error).self) {
            try await first.respondPermission(.init(sessionID: session, toolCallID: tool, optionID: "allow"))
        }
        #expect(try records(rig.core.store).count == 3)
        try await rig.waitUntil("agent answer") { rig.core.sessions[session]?.turn == nil }
        let restarted = try HostCore(configuration: rig.core.configuration)
        #expect(try records(restarted.store).count == 3)
        #expect(try restarted.store.approvals().isEmpty)
        await first.stop()
        await second.stop()
    }

    @Test(arguments: [false, true])
    @HostActor func restartWithdrawsRequestsAndMarksCommittedDeliveryUnknown(_ committed: Bool) throws {
        let rig = try PolicyRig(.unrestricted)
        let (session, tool) = try seed(rig.core)
        if committed {
            _ = try rig.core.store.decideApprovalAudit(
                sessionID: session, toolCallID: tool, optionID: Self.canary,
                actor: Self.firstActor, source: .direct, policy: rig.core.policy, epoch: rig.core.epoch)
        }
        let restarted = try HostCore(configuration: rig.core.configuration)
        let rows = try records(restarted.store)
        #expect(rows.map(\.state) == (committed ? [.requested, .decided, .deliveryFailed] : [.requested, .withdrawn]))
        #expect(rows.last?.reason == .hostRestarted)
        #expect(rows.last?.actor == (committed ? Self.firstActor : .unknown))
        #expect(rows.last?.epoch != rows.first?.epoch)
        #expect(try restarted.store.approvals().isEmpty)
        #expect(throws: (any Error).self) {
            _ = try restarted.store.decideApprovalAudit(
                sessionID: session, toolCallID: tool, optionID: Self.canary, actor: Self.secondActor,
                source: .notification, policy: restarted.policy, epoch: restarted.epoch)
        }
        if committed {
            #expect(throws: ApprovalAuditFailure.notPending) {
                try restarted.store.requestApprovalAudit(
                    HostApprovalAuditRecord(
                        hostID: restarted.hostID, sessionID: session, state: .requested, source: .agent,
                        policyRevision: nil, policyMode: .ordinary, epoch: restarted.epoch),
                    toolCallID: tool, title: Self.canary, optionIDs: [Self.canary])
            }
        }
        #expect(try records(restarted.store).count == rows.count)
    }

    @Test @HostActor func disconnectAndPostDeliveryAppendFailureDoNotReopenDecisions() throws {
        let rig = try PolicyRig(.unrestricted)
        let (session, tool) = try seed(rig.core)
        let live = try #require(rig.core.sessions[session])
        #expect(throws: ApprovalAuditFailure.deliveryUncertain) {
            try rig.core.respondPermission(.init(sessionID: session, toolCallID: tool, optionID: Self.canary))
        }
        #expect(live.pendingPermissions.isEmpty)
        #expect(try records(rig.core.store).last?.reason == .transportUnavailable)
        let (next, nextTool) = try seed(rig.core)
        try rig.core.store.database.execute(
            """
            CREATE TRIGGER fail_delivery BEFORE INSERT ON approval_audit
            WHEN json_extract(NEW.record, '$.state') = 'deliveryFailed'
            BEGIN SELECT RAISE(ABORT, 'injected'); END
            """)
        #expect(throws: ApprovalAuditFailure.deliveryUncertain) {
            try rig.core.respondPermission(.init(sessionID: next, toolCallID: nextTool, optionID: Self.canary))
        }
        try rig.core.store.database.execute("DROP TRIGGER fail_delivery")
        let restarted = try HostCore(configuration: rig.core.configuration)
        #expect(try records(restarted.store).last?.reason == .hostRestarted)
        #expect(try restarted.store.approvals().isEmpty)
    }

    @Test(arguments: [false, true])
    @HostActor func deliveryFailureOrLostReceiptNeverReplays(_ lostReceipt: Bool) async throws {
        let rig = try PolicyRig(.unrestricted)
        let client = try await connect(rig)
        defer { rig.stop() }
        let (session, tool) = try await request(rig, client)
        if lostReceipt {
            try rig.core.store.database.execute(
                """
                CREATE TRIGGER fail_receipt BEFORE INSERT ON approval_audit
                WHEN json_extract(NEW.record, '$.state') = 'deliveryAccepted'
                BEGIN SELECT RAISE(ABORT, 'injected'); END
                """)
        } else {
            rig.core.agents["fake"]?.peer?.close()
        }
        #expect(throws: ApprovalAuditFailure.deliveryUncertain) {
            try rig.core.respondPermission(.init(sessionID: session, toolCallID: tool, optionID: "allow"))
        }
        #expect(rig.core.sessions[session]?.pendingPermissions.isEmpty == true)
        #expect(try rig.core.store.approvals().isEmpty)
        if lostReceipt {
            try await rig.waitUntil("agent received the answer") { rig.core.sessions[session]?.turn == nil }
            try rig.core.store.database.execute("DROP TRIGGER fail_receipt")
        } else {
            #expect(try records(rig.core.store).last?.reason == .transportWriteFailed)
        }
        let restarted = try HostCore(configuration: rig.core.configuration)
        let rows = try records(restarted.store)
        #expect(rows.filter { $0.state == .decided }.count == 1)
        #expect(rows.last?.state == .deliveryFailed)
        #expect(rows.last?.reason == (lostReceipt ? .hostRestarted : .transportWriteFailed))
        await client.stop()
    }

    @Test @HostActor func withdrawalsAndClientCancellationAreDistinctFromDecisions() throws {
        let rig = try PolicyRig(.unrestricted)
        let (session, _) = try seed(rig.core)
        rig.core.withdrawPermissions(of: try #require(rig.core.sessions[session]))
        let (cancelled, tool) = try seed(rig.core)
        #expect(throws: ApprovalAuditFailure.deliveryUncertain) {
            try rig.core.respondPermission(
                .init(sessionID: cancelled, toolCallID: tool, optionID: nil), by: Self.firstActor)
        }
        let rows = try records(rig.core.store)
        #expect(rows.map(\.state) == [.requested, .withdrawn, .requested, .withdrawn, .deliveryFailed])
        #expect(rows[1].reason == .requestEnded && rows[1].actor == .unknown)
        #expect(rows[3].reason == .cancelled && rows[3].actor == Self.firstActor)
        #expect(rows.allSatisfy { $0.selectedOptionID == nil })
    }

    @Test @HostActor func exportAuthorizationCannotBeSpoofedByDisplayNameOrPayload() async throws {
        let rig = try PolicyRig(.unrestricted)
        let (session, tool) = try seed(rig.core)
        for (identity, grants) in [
            (HostClientIdentity.unknown, ClientGrants.owner),
            (Self.firstActor, .owner),
            (.localPeer(uid: 501), ClientGrants(managePlugins: true, manageHost: false, isLocal: true)),
        ] {
            let client = try await connect(rig, identity: identity, grants: grants)
            await #expect(throws: (any Error).self) { _ = try await client.approvalAudit() }
            await client.stop()
        }
        let transport = InProcessTransport { stream in
            await rig.core.accept(stream, identity: Self.firstActor)
        }
        let peer = JSONRPCPeer(channel: try await transport.connect(), label: "spoof") { _ in }
        peer.start()
        defer { peer.close() }
        let payload: JSONValue = .object([
            "sessionID": .string(session.description), "toolCallID": .string(tool), "optionID": .string(Self.canary),
            "actor": .object(["kind": .string("localPeer"), "localUID": .number(0)]),
            "clientInfo": .object(["name": .string(Self.canary)]),
        ])
        // No agent is connected, but the durable decision still identifies the accepting transport.
        await #expect(throws: (any Error).self) {
            _ = try await peer.request(HostProtocol.Method.respondPermission, payload, as: EmptyMessage.self)
        }
        #expect(try records(rig.core.store).first { $0.state == .decided }?.actor == Self.firstActor)
        let owner = try await connect(rig, identity: .localPeer(uid: 501))
        #expect(try await owner.approvalAudit().status == .available)
        rig.core.apply(HostPolicy(mode: .ordinary, capabilities: []))
        await #expect(throws: (any Error).self) { _ = try await owner.approvalAudit() }
        await owner.stop()
    }

    @Test @HostActor func paginationGapsRestartAndCanaryIsolation() throws {
        let rig = try PolicyRig(.unrestricted)
        for _ in 0..<3 { _ = try seed(rig.core) }
        try rig.core.store.appendActivity(
            ActivityEntry(id: 0, at: .now, sessionID: nil, kind: .commandRun, subject: Self.canary, detail: Self.canary)
        )
        let first = rig.core.store.exportApprovalAudit(.init(limit: 1), hostID: rig.core.hostID)
        #expect(first.status == .available && first.cursor.sequence == 1 && first.hasMore)
        let restarted = try HostCore(configuration: rig.core.configuration)
        let next = restarted.store.exportApprovalAudit(
            .init(cursor: first.cursor, limit: 200), hostID: restarted.hostID)
        #expect(next.status == .available && next.cursor.sequence == 6 && !next.hasMore)
        #expect(!next.jsonl.contains(Self.canary))
        for table in ["approval_audit", "approval_audit_heads"] {
            for row in try restarted.store.database.query("SELECT record FROM \(table)") {
                #expect(row[0].text?.contains(Self.canary) == false)
            }
        }
        #expect(
            restarted.store.exportApprovalAudit(
                .init(cursor: .init(hostID: HostID(), sequence: 0)), hostID: restarted.hostID
            ).status == .invalidCursor)
        try restarted.store.database.run("DELETE FROM approval_audit WHERE sequence = 2")
        let gap = restarted.store.exportApprovalAudit(.init(), hostID: restarted.hostID)
        #expect(gap.status == .missingRange && gap.missingRange?.first == 2 && gap.missingRange?.last == 2)
        try restarted.store.database.run("DELETE FROM approval_audit WHERE sequence = 6")
        let tail = restarted.store.exportApprovalAudit(
            .init(cursor: .init(hostID: restarted.hostID, sequence: 5)), hostID: restarted.hostID)
        #expect(tail.status == .missingRange && tail.missingRange?.first == 6)
        try restarted.store.database.run("UPDATE approval_audit SET record = ? WHERE sequence = 1", .text(Self.canary))
        let corrupt = restarted.store.exportApprovalAudit(.init(), hostID: restarted.hostID)
        #expect(corrupt.status == .unavailable && !String(describing: corrupt).contains(Self.canary))
    }

    @Test @HostActor func exportIsBoundedAndUnknownActorsStayUnknown() throws {
        let rig = try PolicyRig(.unrestricted)
        let (session, tool) = try seed(rig.core, optionCount: 64)
        #expect(throws: ApprovalAuditFailure.invalidOption) {
            _ = try rig.core.store.decideApprovalAudit(
                sessionID: session, toolCallID: tool, optionID: "not-offered",
                actor: .unknown, source: .direct, policy: rig.core.policy, epoch: rig.core.epoch)
        }
        for _ in 0..<69 { _ = try seed(rig.core, optionCount: 64) }
        var page = rig.core.store.exportApprovalAudit(.init(limit: Int.max), hostID: rig.core.hostID)
        #expect(page.hasMore && page.status == .available)
        var total = 0
        repeat {
            #expect(page.jsonl.utf8.count <= 256 * 1024)
            #expect(!page.jsonl.contains(Self.canary))
            total += page.jsonl.split(separator: "\n").count
            if !page.hasMore { break }
            page = rig.core.store.exportApprovalAudit(.init(cursor: page.cursor), hostID: rig.core.hostID)
        } while page.status == .available
        #expect(total == 70 && page.cursor.sequence == 70)
        #expect(try records(rig.core.store).allSatisfy { $0.actor == .unknown })
    }

    @Test func localSocketProvenanceComesFromTheKernel() async throws {
        let harness = try HostHarness()
        defer { harness.cleanup() }
        try harness.start()
        let recorder = try await harness.connect()
        let page = try await recorder.client.approvalAudit()
        #expect(page.status == .available)
        let session = try await recorder.client.newSession(
            .init(agentID: "fake", cwd: harness.root.path(), attach: true))
        _ = try await recorder.client.prompt(.init(sessionID: session.id, text: "permission"))
        try await recorder.wait("approval") { await !$0.mirror(session.id).state.pendingPermissions.isEmpty }
        let tool = try #require(await recorder.mirror(session.id).state.pendingPermissions.first?.toolCallID)
        try await recorder.client.respondPermission(.init(sessionID: session.id, toolCallID: tool, optionID: "allow"))
        let exported = try await recorder.client.approvalAudit()
        #expect(exported.jsonl.contains("localPeer"))
        #expect(exported.jsonl.contains("\"localUID\":\(getuid())"))
        await recorder.stop()
    }

    @HostActor private func connect(
        _ rig: PolicyRig, identity: HostClientIdentity = .unknown, grants: ClientGrants = .owner
    ) async throws -> NativeHostClient {
        let client = NativeHostClient(
            transport: InProcessTransport { stream in await rig.core.accept(stream, grants: grants, identity: identity)
            },
            clientInfo: PeerInfo(name: Self.canary, version: "1", build: "1"))
        await client.start()
        _ = try await client.connected()
        return client
    }

    @HostActor private func request(
        _ rig: PolicyRig, _ client: NativeHostClient
    ) async throws -> (HostSessionID, String) {
        try await client.syncAgents([rig.agentSpec()])
        let session = try await client.newSession(.init(agentID: "fake", cwd: rig.root.path()))
        _ = try await client.prompt(.init(sessionID: session.id, text: "permission"))
        try await rig.waitUntil("approval") { rig.core.sessions[session.id]?.pendingPermissions.isEmpty == false }
        let tool = try #require(rig.core.sessions[session.id]?.pendingPermissions.keys.first)
        #expect(try records(rig.core.store).map(\.state) == [.requested])
        return (session.id, tool)
    }

    private func answer(
        _ client: NativeHostClient, _ session: HostSessionID, _ tool: String, _ notice: Int64,
        _ notification: Bool, _ option: String
    ) async -> Bool {
        do {
            if notification { return try await client.act(on: notice, option == "allow" ? .allow : .reject) == .done }
            try await client.respondPermission(.init(sessionID: session, toolCallID: tool, optionID: option))
            return true
        } catch { return false }
    }

    @HostActor private func seed(_ core: HostCore, optionCount: Int = 1) throws -> (HostSessionID, String) {
        let record = StoredSession(
            id: HostSessionID(), agentID: "fake", agentSessionID: nil, cwd: "/fixture", parentID: nil, origin: .user)
        try core.store.insertSession(record)
        let session = HostSession(record: record, agentName: Self.canary, phase: .idle, needsLoad: false)
        core.sessions[record.id] = session
        session.pendingPermissions[Self.canary] = .int(1)
        try core.store.requestApprovalAudit(
            HostApprovalAuditRecord(
                hostID: core.hostID, sessionID: record.id, state: .requested, source: .agent,
                policyRevision: core.policy.revision,
                policyMode: .init(rawValue: core.policy.mode.rawValue) ?? .unknown, epoch: core.epoch),
            toolCallID: Self.canary, title: Self.canary,
            optionIDs: optionCount == 1 ? [Self.canary] : (0..<optionCount).map { Self.canary + String($0) })
        return (record.id, Self.canary)
    }

    private func records(_ store: HostStore) throws -> [HostApprovalAuditRecord] {
        try store.database.query("SELECT record FROM approval_audit ORDER BY sequence").map { row in
            let text = try #require(row[0].text)
            return try JSONDecoder().decode(HostApprovalAuditRecord.self, from: Data(text.utf8))
        }
    }
}
