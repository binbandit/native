import Foundation

/// Plans retention and erasure as a dry run: a pure function of the inventory, a validated policy,
/// the hold authority, the roots the caller approved, the adapters that exist, the tombstones kept
/// and what each store's owner listed. It touches no file, network, process or timer: everything
/// it knows, it was given.
///
/// Precedence, per copy: a confirmed legal hold wins over everything. Otherwise a record is due
/// because someone asked, its retention period expired or its tombstone says it shouldn't be back,
/// and a due copy is planned only when nothing stands in the way. An unusable policy or hold
/// authority, an unknown time, owner or path, an unapproved root, an offline host or a missing
/// adapter each keeps it from being planned, and every one of them is reported.
public struct DataLifecyclePlanner: Sendable {
    public let inventory: DataStoreInventory
    public let policy: DataLifecyclePolicy
    public let holds: LegalHoldAuthority
    public let roots: DataApprovedRoots
    public let adapters: DataAdapterSupport
    public let tombstones: DataTombstoneLedger

    public init(
        inventory: DataStoreInventory = .native, policy: DataLifecyclePolicy, holds: LegalHoldAuthority,
        roots: DataApprovedRoots, adapters: DataAdapterSupport = .none, tombstones: DataTombstoneLedger = .init()
    ) {
        self.inventory = inventory
        self.policy = policy
        self.holds = holds
        self.roots = roots
        self.adapters = adapters
        self.tombstones = tombstones
    }

    public func plan(
        _ request: DataLifecycleRequest, reports: [DataStoreID: DataStoreReport], clock: DataPlanningClock
    ) -> DataLifecyclePlan {
        let scope = (request.stores ?? defaultScope(for: request.purpose)).sorted()
        var unaccounted: [DataUnaccountedStore] = []
        var listed: [(entry: DataStoreEntry, records: [DataRecord])] = []
        for store in scope {
            guard let entry = inventory.entry(store) else {
                unaccounted.append(DataUnaccountedStore(store: store, reason: .notInInventory))
                continue
            }
            switch reports[store] {
            case .listed(let records):
                listed.append((entry, records))
                if Set(records.map(\.key)).count != records.count || records.contains(where: \.copies.isEmpty) {
                    unaccounted.append(DataUnaccountedStore(store: store, reason: .listingInconsistent))
                }
            case .unavailable: unaccounted.append(DataUnaccountedStore(store: store, reason: .listingUnavailable))
            case nil: unaccounted.append(DataUnaccountedStore(store: store, reason: Self.unlistedReason(entry)))
            }
        }

        // Every record's verdict first, so a shared copy can tell whether all its users are going.
        let verdicts = listed.map { item in
            item.records.map { verdict(for: $0, entry: item.entry, request: request, clock: clock) }
        }
        // Only a record that is listed, due and not held can let a shared copy go: a user that's
        // missing from the listings, or held through a parent another record doesn't know about,
        // keeps it.
        var going: Set<DataRecordKey> = []
        for (item, itemVerdicts) in zip(listed, verdicts) {
            for (record, verdict) in zip(item.records, itemVerdicts) {
                if case .due = verdict, !holds.isHolding(record, in: item.entry.id) { going.insert(record.key) }
            }
        }

        var outcomes: [DataCopyOutcome] = []
        for (item, itemVerdicts) in zip(listed, verdicts) {
            for (record, verdict) in zip(item.records, itemVerdicts) where verdict != .outOfScope {
                for copy in record.copies {
                    outcomes.append(
                        outcome(
                            for: copy, of: record, entry: item.entry, verdict: verdict, going: going, request: request))
                }
            }
        }
        outcomes.sort {
            ($0.store, $0.record, $0.copy, $0.operation.value) < ($1.store, $1.record, $1.copy, $1.operation.value)
        }

        let id = DataPlanID(
            "plan-"
                + StableDigest.of(
                    [
                        request.id.value, Self.canonical(request.purpose), policy.revision?.value ?? "-",
                        holds.state.rawValue, holds.revision ?? "-",
                    ]
                        + outcomes.map { "\($0.operation)=\($0.disposition.rawValue)\($0.reasons)" }
                        + unaccounted.map { "\($0.store.rawValue)!\($0.reason.rawValue)" }))
        return DataLifecyclePlan(
            id: id, request: request, policyRevision: policy.revision, holdRevision: holds.revision,
            plannedAt: clock.now, outcomes: outcomes, unaccounted: unaccounted,
            status: Self.status(of: outcomes, unaccounted: unaccounted))
    }

    // MARK: - Records

    enum Verdict: Equatable {
        /// An erasure that doesn't name it: no outcome.
        case outOfScope
        case due(DataLifecycleReason)
        case kept(DataLifecycleReason)
        case undetermined(DataLifecycleReason)
    }

    private func verdict(
        for record: DataRecord, entry: DataStoreEntry, request: DataLifecycleRequest, clock: DataPlanningClock
    ) -> Verdict {
        if tombstones.tombstone(for: record.key, in: entry.id) != nil { return .due(.tombstoned) }
        switch request.purpose {
        case .erasure(let keys):
            return keys.isDisjoint(with: record.keys) ? .outOfScope : .due(.requested)
        case .retention:
            guard case .policy(let key) = entry.retention else { return .kept(.noRetentionRule) }
            guard policy.isAvailable else { return .undetermined(.policyUnavailable) }
            switch policy.retention(key) {
            case .unusable: return .undetermined(.retentionPolicyUnusable)
            case .unlimited: return .kept(.noRetentionPeriod)
            case .days(let days):
                guard !clock.hasGoneBack else { return .undetermined(.clockWentBack) }
                // The newest time the owner knows sets the age, so an older stamp never ages it more.
                guard let newest = record.timestamps.max() else { return .undetermined(.timestampUnknown) }
                guard newest <= clock.now else { return .undetermined(.timestampAfterPlanningTime) }
                // Whole days of 86,400 seconds, as search's own retention counts them; a record last
                // active exactly at the cutoff is kept.
                let cutoff = clock.now.addingTimeInterval(-Double(days) * 86_400)
                return newest < cutoff ? .due(.retentionExpired) : .kept(.notExpired)
            }
        }
    }

    // MARK: - Copies

    private func outcome(
        for copy: DataRecordCopy, of record: DataRecord, entry: DataStoreEntry, verdict: Verdict,
        going: Set<DataRecordKey>, request: DataLifecycleRequest
    ) -> DataCopyOutcome {
        let store = entry.id
        let required = copy.kind.requiredCapabilities(tombstones: entry.needsTombstones)
        let held = holds.holds(covering: record, copy: copy, in: store)
        let reasons: [DataLifecycleReason] =
            if !held.isEmpty {
                held.map(DataLifecycleReason.legalHold)
            } else {
                switch verdict {
                case .outOfScope: []
                case .kept(let reason), .undetermined(let reason): [reason]
                case .due(let reason):
                    [reason]
                        + Set(obstacles(for: copy, entry: entry, going: going, required: required)).sorted()
                }
            }
        let blocking = reasons.map(\.disposition).filter { $0 != .planned }
        let location = copy.location.map { [$0.root.kind.rawValue, $0.root.instance ?? ""] + $0.components } ?? ["-"]
        return DataCopyOutcome(
            operation: DataOperationID(
                "op-"
                    + StableDigest.of(
                        [request.id.value, store.rawValue, record.key.description, copy.kind.rawValue] + location)),
            record: record.key, store: store, copy: copy.kind, location: copy.location,
            disposition: blocking.max() ?? .planned, reasons: reasons, requiredCapabilities: required)
    }

    /// Everything that keeps a due copy from being planned.
    private func obstacles(
        for copy: DataRecordCopy, entry: DataStoreEntry, going: Set<DataRecordKey>,
        required: Set<DataAdapterCapability>
    ) -> [DataLifecycleReason] {
        var obstacles: [DataLifecycleReason] = []
        if !policy.isAvailable { obstacles.append(.policyUnavailable) }
        switch holds.state {
        case .confirmed: break
        case .unavailable: obstacles.append(.holdAuthorityUnavailable)
        case .malformed: obstacles.append(.holdAuthorityMalformed)
        }
        if entry.integration != .verified { obstacles.append(.integrationUnknown) }
        if entry.support.delete == .notApplicable { obstacles.append(.noUserData) }
        obstacles += ownershipObstacles(copy.ownership, entry: entry)

        let specs = entry.copies(copy.kind)
        if specs.isEmpty { obstacles.append(.copyNotInInventory) }
        if let path = copy.location {
            if !path.isConfined {
                obstacles.append(.locationOutsideRoot)
            } else {
                if !specs.contains(where: { $0.location.contains(path) }) { obstacles.append(.locationOutsideStore) }
                if roots.resolve(path) == nil { obstacles.append(.rootNotApproved) }
            }
            switch copy.link {
            case .regular: break
            case .symbolicLink: obstacles.append(.symbolicLink)
            case .unknown: obstacles.append(.linkStateUnknown)
            }
        } else if !specs.isEmpty, specs.allSatisfy({ if case .file = $0.location { true } else { false } }) {
            obstacles.append(.locationUnknown)
        }

        switch copy.availability {
        case .local, .remoteOnline: break
        case .remoteOffline: obstacles.append(.remoteOffline)
        case .unknown: obstacles.append(.availabilityUnknown)
        }
        if !copy.sharedWith.isSubset(of: going) { obstacles.append(.sharedWithKeptRecord) }
        obstacles += required.subtracting(adapters.capabilities(of: entry.id)).map(DataLifecycleReason.adapterMissing)
        return obstacles
    }

    /// The owner's word has to match the inventory's, and only Native's own copies, or an agent's
    /// through an adapter that agent supports, can be removed.
    private func ownershipObstacles(_ reported: DataOwnership, entry: DataStoreEntry) -> [DataLifecycleReason] {
        if reported == .unknown || entry.ownership == .unknown { return [.ownershipUnknown] }
        if reported != entry.ownership { return [.ownershipMismatch] }
        return switch entry.ownership {
        case .native: []
        case .externalAgent: adapters.capabilities(of: entry.id).isEmpty ? [.externallyOwned] : []
        case .customer: [.customerOwned]
        case .operatingSystem: [.systemOwned]
        case .unknown: [.ownershipUnknown]
        }
    }

    // MARK: - Scope and status

    private func defaultScope(for purpose: DataLifecycleRequest.Purpose) -> Set<DataStoreID> {
        Set(
            inventory.entries.filter { entry in
                switch purpose {
                case .retention: if case .policy = entry.retention { true } else { false }
                case .erasure: entry.support.delete != .notApplicable
                }
            }.map(\.id))
    }

    private static func unlistedReason(_ entry: DataStoreEntry) -> DataUnaccountedStore.Reason {
        if entry.integration != .verified { return .integrationUnknown }
        return entry.ownership == .native ? .notListed : .ownedOutsideNative
    }

    static func status(of outcomes: [DataCopyOutcome], unaccounted: [DataUnaccountedStore]) -> DataLifecyclePlan.Status
    {
        let anyPlanned = outcomes.contains { $0.disposition == .planned }
        let settled =
            unaccounted.isEmpty
            && outcomes.allSatisfy { outcome in
                outcome.disposition == .planned
                    || (outcome.disposition == .kept && outcome.reasons.allSatisfy(\.isNotDue))
            }
        return switch (anyPlanned, settled) {
        case (true, true): .complete
        case (true, false): .partial
        case (false, true): .nothingToDo
        case (false, false): .blocked
        }
    }

    private static func canonical(_ purpose: DataLifecycleRequest.Purpose) -> String {
        switch purpose {
        case .retention: "retention"
        case .erasure(let keys): "erasure:" + keys.sorted().map(\.description).joined(separator: ",")
        }
    }
}
