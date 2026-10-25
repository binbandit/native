import Foundation
import NativePolicy
import Testing

@testable import NativeDataLifecycle

/// The planner's precedence and fail-closed rules, on synthetic records only.
@Suite struct DataLifecyclePlanTests {
    typealias W = SyntheticWorkspace

    // MARK: - Legal holds

    @Test func holdWinsOverExpiredRetention() throws {
        let expired = W.searchRecord(W.alpha, lastActive: W.ago(days: 90))
        let holds = LegalHoldAuthority.confirmed(
            revision: "holds-2", holds: [LegalHold(id: "matter-7", scope: .records([W.alpha]))])
        let plan = W.planner(holds: holds).plan(
            try W.retention(), reports: [.searchIndex: .listed([expired])], clock: W.clock)

        #expect(plan.dispositions(W.alpha).values.allSatisfy { $0 == .held })
        #expect(plan.reasons(W.alpha) == [.legalHold("matter-7")])
        #expect(plan.operations.isEmpty)
        #expect(plan.status == .blocked)
        #expect(plan.holdRevision == "holds-2")
    }

    @Test func holdOnAProjectOrStoreWinsOverARequest() throws {
        let records = [
            W.searchRecord(W.alpha, lastActive: W.now), W.searchRecord(W.beta, lastActive: W.now, parents: []),
        ]
        let byProject = LegalHoldAuthority.confirmed(
            revision: "h", holds: [LegalHold(id: "project-hold", scope: .records([W.project]))])
        let plan = W.planner(holds: byProject).plan(
            try W.erasure([W.alpha, W.beta]), reports: [.searchIndex: .listed(records)], clock: W.clock)
        #expect(plan.dispositions(W.alpha).values.allSatisfy { $0 == .held })
        #expect(plan.dispositions(W.beta).values.allSatisfy { $0 == .planned })
        #expect(plan.status == .partial)

        let byStore = LegalHoldAuthority.confirmed(
            revision: "h", holds: [LegalHold(id: "store-hold", scope: .stores([.searchIndex]))])
        let held = W.planner(holds: byStore).plan(
            try W.erasure([W.alpha, W.beta]), reports: [.searchIndex: .listed(records)], clock: W.clock)
        #expect(held.outcomes.allSatisfy { $0.disposition == .held })
        #expect(held.status == .blocked)
    }

    @Test func unreadableOrMalformedHoldsPlanNothingDestructive() throws {
        let records = [W.searchRecord(W.alpha, lastActive: W.ago(days: 90)), W.searchRecord(W.beta, lastActive: W.now)]
        let malformed: [LegalHoldAuthority] = [
            .confirmed(revision: "", holds: []),
            .confirmed(revision: "h", holds: [LegalHold(id: "", scope: .everything)]),
            .confirmed(revision: "h", holds: [LegalHold(id: "a", scope: .records([]))]),
            .confirmed(
                revision: "h",
                holds: [LegalHold(id: "a", scope: .everything), LegalHold(id: "a", scope: .stores([.drafts]))]),
        ]
        for (authority, reason) in [(LegalHoldAuthority.unavailable, DataLifecycleReason.holdAuthorityUnavailable)]
            + malformed.map({ ($0, DataLifecycleReason.holdAuthorityMalformed) })
        {
            let plan = W.planner(holds: authority).plan(
                try W.retention(), reports: [.searchIndex: .listed(records)], clock: W.clock)
            #expect(plan.dispositions(W.alpha).values.allSatisfy { $0 == .unknown })
            #expect(plan.reasons(W.alpha).contains(reason))
            // A record that isn't due stays kept: nothing destructive was ever on the table for it.
            #expect(plan.dispositions(W.beta).values.allSatisfy { $0 == .kept })
            #expect(plan.operations.isEmpty)
            #expect(plan.status == .blocked)
        }
    }

    // MARK: - Policy

    @Test func unusableRetentionPolicyDeletesNothingByIt() throws {
        let twoDaysOld = [W.searchRecord(W.alpha, lastActive: W.ago(days: 2))]
        // The policy layer fails closed to one day for an unusable value; for deletion that would
        // delete more, so the planner treats it as unknown instead.
        let native = PolicyLoader.load(from: StaticPolicySource(managed: ["policy.search.retentionDays": "thirty"]))
        #expect(native.searchRetentionDays == 1)
        let unusable = W.planner(policy: DataLifecyclePolicy(native)).plan(
            try W.retention(), reports: [.searchIndex: .listed(twoDaysOld)], clock: W.clock)
        #expect(unusable.reasons(W.alpha) == [.retentionPolicyUnusable])
        #expect(unusable.status == .blocked)

        for policy in [DataLifecyclePolicy.unavailable, W.policy(status: .malformed), W.policy(status: .unavailable)] {
            #expect(!policy.isAvailable)
            let retention = W.planner(policy: policy).plan(
                try W.retention(), reports: [.searchIndex: .listed(twoDaysOld)], clock: W.clock)
            #expect(retention.reasons(W.alpha) == [.policyUnavailable])
            let erasure = W.planner(policy: policy).plan(
                try W.erasure([W.alpha]), reports: [.searchIndex: .listed(twoDaysOld)], clock: W.clock)
            #expect(erasure.reasons(W.alpha).contains(.policyUnavailable))
            #expect(erasure.operations.isEmpty)
        }
    }

    @Test func noRetentionPeriodKeepsEverythingAndSaysWhichPolicy() throws {
        let plan = W.planner(policy: W.policy()).plan(
            try W.retention(),
            reports: [.searchIndex: .listed([W.searchRecord(W.alpha, lastActive: W.ago(days: 900))])],
            clock: W.clock)
        #expect(plan.reasons(W.alpha) == [.noRetentionPeriod])
        #expect(plan.status == .nothingToDo)
        #expect(plan.policyRevision == nil)
        #expect(W.thirtyDays.revision != nil)
        let managed = W.planner().plan(try W.retention(), reports: [.searchIndex: .listed([])], clock: W.clock)
        #expect(managed.policyRevision == W.thirtyDays.revision)
    }

    // MARK: - Time

    @Test func theExactCutoffIsKeptAndOneSecondPastIsDue() throws {
        let cutoff = W.ago(days: 30)
        let atCutoff = W.searchRecord(W.alpha, lastActive: cutoff)
        let past = W.searchRecord(W.beta, lastActive: cutoff.addingTimeInterval(-1))
        // The newest time decides: an old creation date doesn't age a record that's been active since.
        var touched = W.searchRecord(DataRecordKey(.session, "task-gamma"), lastActive: W.ago(days: 400))
        touched.timestamps.append(W.ago(days: 1))
        let plan = W.planner().plan(
            try W.retention(), reports: [.searchIndex: .listed([atCutoff, past, touched])], clock: W.clock)

        #expect(plan.reasons(W.alpha) == [.notExpired])
        #expect(plan.dispositions(W.beta).values.allSatisfy { $0 == .planned })
        #expect(plan.reasons(W.beta) == [.retentionExpired])
        #expect(plan.reasons(touched.key) == [.notExpired])
        #expect(plan.status == .complete)
    }

    @Test func clockTroubleNeverBroadensDeletion() throws {
        let expired = W.searchRecord(W.alpha, lastActive: W.ago(days: 90))
        let future = W.searchRecord(W.beta, lastActive: W.now.addingTimeInterval(60))
        let undated = W.searchRecord(DataRecordKey(.session, "task-gamma"), lastActive: nil)
        let reports: [DataStoreID: DataStoreReport] = [.searchIndex: .listed([expired, future, undated])]

        let wentBack = DataPlanningClock(now: W.now, trustedFloor: W.now.addingTimeInterval(3_600))
        let rolledBack = W.planner().plan(try W.retention(), reports: reports, clock: wentBack)
        #expect(rolledBack.reasons(W.alpha) == [.clockWentBack])
        #expect(rolledBack.operations.isEmpty)

        let steady = W.planner().plan(try W.retention(), reports: reports, clock: W.clock)
        #expect(steady.reasons(W.beta) == [.timestampAfterPlanningTime])
        #expect(steady.reasons(undated.key) == [.timestampUnknown])
        #expect(steady.operations.map(\.record) == [W.alpha, W.alpha, W.alpha])
        #expect(steady.status == .partial)

        // An explicit request doesn't depend on the clock.
        let erasure = W.planner().plan(try W.erasure([W.beta, undated.key]), reports: reports, clock: wentBack)
        #expect(erasure.operations.count == 6)
    }

    // MARK: - Reach

    @Test func anOfflineHostsCopyIsUnreachable() throws {
        func remote(_ id: String, _ availability: DataAvailability) -> DataRecord {
            DataRecord(
                DataRecordKey(.session, id),
                copies: [DataRecordCopy(.primary, availability: availability)])
        }
        let records = [remote("offline", .remoteOffline), remote("online", .remoteOnline), remote("unsure", .unknown)]
        let plan = W.planner().plan(
            try W.erasure(Set(records.map(\.key)), stores: [.remoteHostCopies]),
            reports: [.remoteHostCopies: .listed(records)], clock: W.clock)

        #expect(plan.reasons(DataRecordKey(.session, "offline")) == [.requested, .remoteOffline])
        #expect(plan.dispositions(DataRecordKey(.session, "offline"))[.primary] == .unreachable)
        #expect(plan.dispositions(DataRecordKey(.session, "online"))[.primary] == .planned)
        #expect(plan.reasons(DataRecordKey(.session, "unsure")) == [.requested, .availabilityUnknown])
        #expect(plan.status == .partial)
    }

    @Test func missingAdapterCapabilitiesStayExplicit() throws {
        let record = W.searchRecord(W.alpha, lastActive: W.ago(days: 90))
        let withoutCompaction = DataAdapterSupport([.searchIndex: [.delete, .verify, .tombstone]])
        let plan = W.planner(adapters: withoutCompaction).plan(
            try W.retention(), reports: [.searchIndex: .listed([record])], clock: W.clock)
        #expect(
            plan.dispositions(W.alpha) == [
                .primary: .planned, .writeAheadLog: .unsupported, .sharedMemory: .unsupported,
            ])
        #expect(plan.reasons(W.alpha, .writeAheadLog) == [.retentionExpired, .adapterMissing(.compact)])
        #expect(plan.status == .partial)

        // Today no store has an adapter, so nothing is ever planned.
        let today = W.planner(adapters: .none).plan(
            try W.retention(), reports: [.searchIndex: .listed([record])], clock: W.clock)
        #expect(today.outcomes.allSatisfy { $0.disposition == .unsupported })
        #expect(today.reasons(W.alpha).contains(.adapterMissing(.tombstone)))
        #expect(today.status == .blocked)
    }

    @Test func unlistedStoresKeepAPlanFromCompleting() throws {
        let plan = W.planner().plan(
            try W.erasure([W.alpha], stores: [.searchIndex, .drafts, .agentHistories, .approvalAudit, .automation]),
            reports: [.searchIndex: .listed([W.searchRecord(W.alpha, lastActive: W.now)]), .automation: .unavailable],
            clock: W.clock)
        #expect(
            plan.unaccounted
                == [
                    DataUnaccountedStore(store: .agentHistories, reason: .ownedOutsideNative),
                    DataUnaccountedStore(store: .drafts, reason: .notListed),
                    DataUnaccountedStore(store: .approvalAudit, reason: .integrationUnknown),
                    DataUnaccountedStore(store: .automation, reason: .listingUnavailable),
                ].sorted { $0.store < $1.store })
        #expect(plan.operations.count == 3)
        #expect(plan.status == .partial)

        // A record listed twice, or without copies, makes the listing untrustworthy as a whole.
        for records in [
            [W.searchRecord(W.alpha, lastActive: W.now), W.searchRecord(W.alpha, lastActive: W.now)],
            [W.searchRecord(W.alpha, lastActive: W.now), DataRecord(W.beta, copies: [])],
        ] {
            let inconsistent = W.planner().plan(
                try W.erasure([W.alpha, W.beta]), reports: [.searchIndex: .listed(records)], clock: W.clock)
            #expect(
                inconsistent.unaccounted == [DataUnaccountedStore(store: .searchIndex, reason: .listingInconsistent)])
            #expect(inconsistent.status == .partial)
        }
    }
}
