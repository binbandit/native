import Foundation
import NativePolicy
import Testing

@testable import NativeDataLifecycle

/// A made-up workspace for the planner tests. Every root sits under one synthetic approved root
/// that names no real person, machine or folder, and nothing here is ever looked up on disk.
enum SyntheticWorkspace {
    static let base = "/synthetic-approved-root"

    static let repository = DataRoot(.repository, instance: "repo-one")

    static let roots = DataApprovedRoots([
        DataRoot(.appSupport): "\(base)/AppSupport",
        DataRoot(.hostData): "\(base)/HostDir",
        DataRoot(.nativeHome): "\(base)/native-home",
        DataRoot(.caches): "\(base)/Caches",
        DataRoot(.temporary): "\(base)/tmp",
        repository: "\(base)/repositories/repo-one",
    ])

    static let now = Date(timeIntervalSince1970: 1_800_000_000)
    static let clock = DataPlanningClock(now: now)

    static let alpha = DataRecordKey(.session, "task-alpha")
    static let beta = DataRecordKey(.session, "task-beta")
    static let project = DataRecordKey(.project, "project-one")

    static let noHolds = LegalHoldAuthority.confirmed(revision: "holds-1", holds: [])

    /// Every capability for every store, so a test sees only the obstacle it sets up.
    static let everyAdapter = DataAdapterSupport(
        Dictionary(uniqueKeysWithValues: DataStoreID.allCases.map { ($0, Set(DataAdapterCapability.allCases)) }))

    static func ago(days: Double) -> Date { now.addingTimeInterval(-days * 86_400) }

    static func policy(
        _ managed: [String: Any] = [:], status: ManagedSourceStatus = .available
    )
        -> DataLifecyclePolicy
    {
        DataLifecyclePolicy(PolicyLoader.load(from: StaticPolicySource(managed: managed, status: status)))
    }

    static let thirtyDays = policy(["policy.search.retentionDays": 30])

    static func planner(
        policy: DataLifecyclePolicy = thirtyDays, holds: LegalHoldAuthority = noHolds,
        roots: DataApprovedRoots = roots, adapters: DataAdapterSupport = everyAdapter,
        tombstones: DataTombstoneLedger = .init()
    ) -> DataLifecyclePlanner {
        DataLifecyclePlanner(policy: policy, holds: holds, roots: roots, adapters: adapters, tombstones: tombstones)
    }

    static func path(_ kind: DataRootKind, _ components: String...) -> DataRelativePath {
        DataRelativePath(DataRoot(kind), components)
    }

    /// A task's row in the search index, with its copies in the database, log and index file.
    static func searchRecord(
        _ key: DataRecordKey, lastActive: Date?, parents: Set<DataRecordKey> = [project]
    )
        -> DataRecord
    {
        DataRecord(
            key, parents: parents, timestamps: lastActive.map { [$0] } ?? [],
            copies: [
                DataRecordCopy(.primary, at: path(.appSupport, "search-index.sqlite")),
                DataRecordCopy(.writeAheadLog, at: path(.appSupport, "search-index.sqlite-wal")),
                DataRecordCopy(.sharedMemory, at: path(.appSupport, "search-index.sqlite-shm")),
            ])
    }

    /// A pasted image folder, optionally shared with other tasks.
    static func attachment(_ key: DataRecordKey, sharedWith: Set<DataRecordKey> = []) -> DataRecord {
        DataRecord(
            key, parents: [project],
            copies: [
                DataRecordCopy(
                    .temporary, at: path(.temporary, "Native Attachments", "attachment-1"), sharedWith: sharedWith)
            ])
    }

    static func retention(_ id: String = "retention-1") throws -> DataLifecycleRequest {
        try #require(DataLifecycleRequest(id: id, purpose: .retention))
    }

    static func erasure(
        _ keys: Set<DataRecordKey>, id: String = "erasure-1", stores: Set<DataStoreID>? = [.searchIndex]
    ) throws -> DataLifecycleRequest {
        try #require(DataLifecycleRequest(id: id, purpose: .erasure(keys), stores: stores))
    }

    /// The fixture manifest: approved roots and what each store's owner listed, for a whole-inventory plan.
    struct Manifest: Decodable {
        struct Root: Decodable {
            let kind: DataRootKind
            let instance: String?
            let path: String
        }

        let roots: [Root]
        let stores: [String: [DataRecord]]

        var approvedRoots: DataApprovedRoots {
            DataApprovedRoots(
                Dictionary(uniqueKeysWithValues: roots.map { (DataRoot($0.kind, instance: $0.instance), $0.path) }))
        }

        var reports: [DataStoreID: DataStoreReport] {
            var reports: [DataStoreID: DataStoreReport] = [:]
            for (store, records) in stores {
                if let id = DataStoreID(rawValue: store) { reports[id] = .listed(records) }
            }
            return reports
        }

        static func load() throws -> Manifest {
            guard
                let url = Bundle.module.url(
                    forResource: "synthetic-workspace", withExtension: "json", subdirectory: "Fixtures")
            else { throw CocoaError(.fileNoSuchFile) }
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            return try decoder.decode(Manifest.self, from: Data(contentsOf: url))
        }
    }
}

extension DataLifecyclePlan {
    func dispositions(_ record: DataRecordKey) -> [DataCopyKind: DataCopyOutcome.Disposition] {
        Dictionary(uniqueKeysWithValues: outcomes(for: record).map { ($0.copy, $0.disposition) })
    }

    func reasons(_ record: DataRecordKey, _ copy: DataCopyKind = .primary) -> [DataLifecycleReason] {
        outcomes(for: record).first { $0.copy == copy }?.reasons ?? []
    }
}
