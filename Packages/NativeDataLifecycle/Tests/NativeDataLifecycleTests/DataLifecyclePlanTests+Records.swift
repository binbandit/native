import Foundation
import Testing

@testable import NativeDataLifecycle

/// Ownership, paths, sharing, tombstones and identifiers: what the caller says about each copy, and
/// what the planner refuses to assume.
extension DataLifecyclePlanTests {
    @Test func ownershipPathsAndLinksAreTakenFromMetadataOnly() throws {
        func copy(
            _ path: DataRelativePath?, ownership: DataOwnership = .native, link: DataLinkState = .regular
        )
            -> DataRecordCopy
        {
            DataRecordCopy(.primary, at: path, ownership: ownership, link: link)
        }
        let cases: [(String, DataRecordCopy, DataLifecycleReason)] = [
            ("unknown-owner", copy(W.path(.appSupport, "search-index.sqlite"), ownership: .unknown), .ownershipUnknown),
            (
                "someone-else", copy(W.path(.appSupport, "search-index.sqlite"), ownership: .customer),
                .ownershipMismatch
            ),
            ("climbs", copy(W.path(.appSupport, "..", "search-index.sqlite")), .locationOutsideRoot),
            ("absolute", copy(W.path(.appSupport, "/search-index.sqlite")), .locationOutsideRoot),
            ("elsewhere-in-root", copy(W.path(.appSupport, "other.sqlite")), .locationOutsideStore),
            ("other-root", copy(W.path(.caches, "search-index.sqlite")), .locationOutsideStore),
            ("no-path", copy(nil), .locationUnknown),
            ("link", copy(W.path(.appSupport, "search-index.sqlite"), link: .symbolicLink), .symbolicLink),
            ("link-unknown", copy(W.path(.appSupport, "search-index.sqlite"), link: .unknown), .linkStateUnknown),
        ]
        let records = cases.map { DataRecord(DataRecordKey(.session, $0.0), copies: [$0.1]) }
        let plan = W.planner().plan(
            try W.erasure(Set(records.map(\.key))), reports: [.searchIndex: .listed(records)], clock: W.clock)
        for (id, _, reason) in cases {
            let outcome = try #require(plan.outcomes(for: DataRecordKey(.session, id)).first)
            #expect(outcome.reasons == [.requested, reason], "\(id)")
            #expect(outcome.disposition == .unknown, "\(id)")
        }
        #expect(plan.status == .blocked)
    }

    @Test func onlyApprovedPlainRootsResolve() throws {
        let roots = DataApprovedRoots([
            DataRoot(.appSupport): "relative/AppSupport",
            DataRoot(.caches): "\(W.base)/../Caches",
            DataRoot(.temporary): "/",
            DataRoot(.keychain): "\(W.base)/keychain",
            DataRoot(.hostData): "\(W.base)/HostDir",
        ])
        #expect(
            roots.rejected == [DataRoot(.appSupport), DataRoot(.caches), DataRoot(.temporary), DataRoot(.keychain)])
        #expect(roots.resolve(W.path(.hostData, "host.sqlite")) == "\(W.base)/HostDir/host.sqlite")
        #expect(roots.resolve(W.path(.hostData, "..", "host.sqlite")) == nil)

        let record = W.searchRecord(W.alpha, lastActive: W.now)
        let plan = W.planner(roots: roots).plan(
            try W.erasure([W.alpha]), reports: [.searchIndex: .listed([record])], clock: W.clock)
        #expect(plan.outcomes.allSatisfy { $0.disposition == .unreachable && $0.reasons.contains(.rootNotApproved) })
    }

    @Test func storesOutsideNativeAreNeverPlanned() throws {
        let history = DataRecord(W.alpha, copies: [DataRecordCopy(.primary, ownership: .externalAgent)])
        let objects = DataRecord(
            DataRecordKey(.repository, "repo-one"), copies: [DataRecordCopy(.gitObjects, ownership: .customer)])
        let clone = DataRecord(
            DataRecordKey(.repository, "clone-one"),
            copies: [DataRecordCopy(.primary, at: DataRelativePath(DataRoot(.userChosen), ["clone-one"]))])
        let request = try W.erasure(
            [W.alpha, objects.key, clone.key], stores: [.agentHistories, .repositoryHistory, .pullRequestClones])
        let reports: [DataStoreID: DataStoreReport] = [
            .agentHistories: .listed([history]), .repositoryHistory: .listed([objects]),
            .pullRequestClones: .listed([clone]),
        ]
        let plan = W.planner(adapters: .none).plan(request, reports: reports, clock: W.clock)
        #expect(plan.reasons(W.alpha).contains(.externallyOwned))
        #expect(plan.reasons(objects.key, .gitObjects).contains(.customerOwned))
        #expect(plan.reasons(clone.key).contains(.ownershipUnknown))
        #expect(plan.operations.isEmpty)

        // An agent's store can be planned only through an adapter that agent explicitly supports.
        let explicit = DataAdapterSupport([.agentHistories: [.delete, .verify]])
        let withAdapter = W.planner(adapters: explicit).plan(request, reports: reports, clock: W.clock)
        #expect(withAdapter.dispositions(W.alpha)[.primary] == .planned)
        #expect(withAdapter.dispositions(objects.key)[.gitObjects] == .unsupported)
    }

    @Test func aSharedCopyGoesOnlyWithEveryRecordUsingIt() throws {
        let records = [W.attachment(W.alpha, sharedWith: [W.beta]), W.attachment(W.beta, sharedWith: [W.alpha])]
        let reports: [DataStoreID: DataStoreReport] = [.attachments: .listed(records)]

        let alone = W.planner().plan(try W.erasure([W.alpha], stores: [.attachments]), reports: reports, clock: W.clock)
        #expect(alone.reasons(W.alpha, .temporary) == [.requested, .sharedWithKeptRecord])
        #expect(alone.dispositions(W.alpha)[.temporary] == .kept)
        #expect(alone.outcomes(for: W.beta).isEmpty)
        #expect(alone.status == .blocked)

        let both = W.planner().plan(
            try W.erasure([W.alpha, W.beta], stores: [.attachments]), reports: reports, clock: W.clock)
        #expect(both.operations.count == 2)
        #expect(both.status == .complete)

        // A user held through a parent the other record's listing doesn't know about still keeps it.
        let betaElsewhere = DataRecord(
            W.beta, parents: [DataRecordKey(.project, "project-two")],
            copies: [
                DataRecordCopy(
                    .temporary, at: W.path(.temporary, "Native Attachments", "attachment-1"), sharedWith: [W.alpha])
            ])
        let projectTwoHeld = LegalHoldAuthority.confirmed(
            revision: "h", holds: [LegalHold(id: "p2", scope: .records([DataRecordKey(.project, "project-two")]))])
        let throughParent = W.planner(holds: projectTwoHeld).plan(
            try W.erasure([W.alpha, W.beta], stores: [.attachments]),
            reports: [.attachments: .listed([records[0], betaElsewhere])], clock: W.clock)
        #expect(throughParent.reasons(W.alpha, .temporary) == [.requested, .sharedWithKeptRecord])
        #expect(throughParent.reasons(W.beta, .temporary) == [.legalHold("p2")])
        #expect(throughParent.operations.isEmpty)

        // A hold on either user keeps the shared copy for both.
        let betaHeld = LegalHoldAuthority.confirmed(
            revision: "h", holds: [LegalHold(id: "b", scope: .records([W.beta]))])
        let held = W.planner(holds: betaHeld).plan(
            try W.erasure([W.alpha, W.beta], stores: [.attachments]), reports: reports, clock: W.clock)
        #expect(held.outcomes.allSatisfy { $0.disposition == .held })
    }

    @Test func aTombstoneKeepsARemovedRecordFromComingBack() throws {
        let erased = W.planner().plan(
            try W.erasure([W.alpha]), reports: [.searchIndex: .listed([W.searchRecord(W.alpha, lastActive: W.now)])],
            clock: W.clock)
        let tombstone = try #require(erased.tombstones.first)
        #expect(erased.tombstones == [tombstone])
        #expect(tombstone.record == W.alpha && tombstone.store == .searchIndex)
        #expect(erased.operations.first { $0.copy == .primary }?.capabilities.contains(.tombstone) == true)

        // Once the removal is done, a reindex can't add it back, and a store that lists it anyway
        // (fresh, so retention alone would keep it) gets it planned for removal again.
        let ledger = DataTombstoneLedger().adding(erased.tombstones)
        #expect(!ledger.permitsImport(of: W.alpha, into: .searchIndex))
        #expect(ledger.permitsImport(of: W.beta, into: .searchIndex))
        #expect(ledger.permitsImport(of: W.alpha, into: .sessionCatalog))
        let reindexed = [W.searchRecord(W.alpha, lastActive: W.now), W.searchRecord(W.beta, lastActive: W.now)]
        let sweep = W.planner(tombstones: ledger).plan(
            try W.retention(), reports: [.searchIndex: .listed(reindexed)], clock: W.clock)
        #expect(sweep.reasons(W.alpha) == [.tombstoned])
        #expect(sweep.dispositions(W.alpha).values.allSatisfy { $0 == .planned })
        #expect(sweep.reasons(W.beta) == [.notExpired])

        // A hold still wins over the tombstone.
        let held = LegalHoldAuthority.confirmed(revision: "h", holds: [LegalHold(id: "a", scope: .records([W.alpha]))])
        let keep = W.planner(holds: held, tombstones: ledger).plan(
            try W.retention(), reports: [.searchIndex: .listed(reindexed)], clock: W.clock)
        #expect(keep.dispositions(W.alpha).values.allSatisfy { $0 == .held })
    }

    @Test func planningAgainResumesTheSameOperations() throws {
        let reports: [DataStoreID: DataStoreReport] = [
            .searchIndex: .listed([
                W.searchRecord(W.alpha, lastActive: W.now), W.searchRecord(W.beta, lastActive: W.now),
            ])
        ]
        let request = try W.erasure([W.alpha, W.beta])
        let first = W.planner().plan(request, reports: reports, clock: W.clock)
        let again = W.planner().plan(
            request, reports: reports, clock: DataPlanningClock(now: W.now.addingTimeInterval(3_600)))
        #expect(again.id == first.id)
        #expect(again.operations.map(\.id) == first.operations.map(\.id))
        #expect(Set(first.operations.map(\.id)).count == first.operations.count)
        #expect(first.operations.allSatisfy { $0.plan == first.id && $0.policyRevision == W.thirtyDays.revision })

        // New policy: a new plan to check against, with the same operations to resume.
        let newPolicy = W.planner(policy: W.policy(["policy.search.retentionDays": 60])).plan(
            request, reports: reports, clock: W.clock)
        #expect(newPolicy.id != first.id)
        #expect(newPolicy.operations.map(\.id) == first.operations.map(\.id))

        // Another request is other work, even for the same records.
        let other = W.planner().plan(
            try W.erasure([W.alpha, W.beta], id: "erasure-2"), reports: reports, clock: W.clock)
        #expect(Set(other.operations.map(\.id)).isDisjoint(with: first.operations.map(\.id)))
    }

    @Test func requestsNeedAnIdAndSomethingToErase() {
        #expect(DataLifecycleRequest(id: "", purpose: .retention) == nil)
        #expect(DataLifecycleRequest(id: "e", purpose: .erasure([])) == nil)
        #expect(DataLifecycleRequest(id: "e", purpose: .erasure([DataRecordKey(.session, "")])) == nil)
        #expect(DataLifecycleRequest(id: "r", purpose: .retention, stores: []) == nil)
    }
}
