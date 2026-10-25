import NativePolicy

/// What the inventory knows about one store: who owns it, what it holds, where each copy lives, how
/// long it's kept today and which lifecycle operations exist for it.
public struct DataStoreEntry: Sendable {
    public let id: DataStoreID
    public let summary: String
    /// Where the store is written and read, relative to the repository root.
    public let owners: [String]
    public let ownership: DataOwnership
    public let integration: DataIntegrationStatus
    public let content: Set<DataContentClass>
    /// What one of its records is about.
    public let records: DataRecordScope
    public let copies: [DataCopySpec]
    public let retention: DataRetentionBasis
    /// What Native already removes on its own or at the user's request, before any lifecycle adapter.
    public let today: String
    public let support: DataSupport
    /// Stores whose contents can recreate this one's records (a reindex, a relisting), so a deletion
    /// here needs a tombstone that keeps them out.
    public let reimportedFrom: [DataStoreID]
    /// The integration job that gives it an adapter; nil when it never gets one.
    public let followUp: DataLifecycleJob?

    init(
        _ id: DataStoreID, _ summary: String, owners: [String], ownership: DataOwnership,
        integration: DataIntegrationStatus = .verified, content: Set<DataContentClass>, records: DataRecordScope,
        copies: [DataCopySpec], retention: DataRetentionBasis, today: String, support: DataSupport,
        reimportedFrom: [DataStoreID] = [], followUp: DataLifecycleJob?
    ) {
        self.id = id
        self.summary = summary
        self.owners = owners
        self.ownership = ownership
        self.integration = integration
        self.content = content
        self.records = records
        self.copies = copies
        self.retention = retention
        self.today = today
        self.support = support
        self.reimportedFrom = reimportedFrom
        self.followUp = followUp
    }

    /// A store can keep one kind of copy in several places (the host's socket and its lock).
    public func copies(_ kind: DataCopyKind) -> [DataCopySpec] {
        copies.filter { $0.kind == kind }
    }

    /// Whether deleting its records leaves something that could bring them back.
    public var needsTombstones: Bool { !reimportedFrom.isEmpty }
}

/// One copy a store keeps of its records.
public struct DataCopySpec: Equatable, Sendable {
    public let kind: DataCopyKind
    public let location: DataLocation
    public let format: DataFormat

    init(_ kind: DataCopyKind, _ location: DataLocation, _ format: DataFormat) {
        self.kind = kind
        self.location = location
        self.format = format
    }
}

public enum DataFormat: Equatable, Sendable {
    /// A SQLite database and the tables that hold records.
    case sqlite(tables: [String])
    case json
    case jsonLines
    case propertyList
    case files
    case gitWorktree
    case gitRefs
    case gitObjects
    case defaults
    case keychain
    /// Whatever its owner chooses.
    case ownerDefined

    public var description: String {
        switch self {
        case .sqlite(let tables): tables.isEmpty ? "SQLite" : "SQLite (\(tables.joined(separator: ", ")))"
        case .json: "JSON"
        case .jsonLines: "JSON Lines"
        case .propertyList: "property list"
        case .files: "files"
        case .gitWorktree: "git worktree"
        case .gitRefs: "git refs and config"
        case .gitObjects: "git objects"
        case .defaults: "defaults"
        case .keychain: "Keychain items"
        case .ownerDefined: "owner-defined"
        }
    }
}

/// The policy keys that set a retention period Native applies.
public enum DataRetentionKey: CaseIterable, Sendable {
    case searchRetentionDays
}

/// How long a store keeps its records today.
public enum DataRetentionBasis: Equatable, Sendable {
    /// A policy key sets it.
    case policy(DataRetentionKey)
    /// The owner prunes by its own fixed rule, which no policy sets.
    case ownerRule(String)
    /// As long as the record it belongs to (its task, project or pairing).
    case followsRecord(DataRecordScope)
    /// Replaced when its source is fetched or listed again.
    case untilReplaced
    /// Until the user removes it.
    case userManaged
    /// Its owner outside Native decides.
    case external
    /// Not established yet.
    case undetermined

    public var description: String {
        switch self {
        case .policy(let key): "`\(key.policyKey.rawValue)`"
        case .ownerRule(let rule): rule
        case .followsRecord(let scope): "with its \(scope.rawValue)"
        case .untilReplaced: "until replaced"
        case .userManaged: "until the user removes it"
        case .external: "owner decides"
        case .undetermined: "not determined"
        }
    }
}

/// Which lifecycle operations the store has, or could have.
public struct DataSupport: Equatable, Sendable {
    public let export: DataSupportLevel
    public let delete: DataSupportLevel
    public let hold: DataHoldSupport

    public init(export: DataSupportLevel, delete: DataSupportLevel, hold: DataHoldSupport) {
        self.export = export
        self.delete = delete
        self.hold = hold
    }

    /// Native-owned content without an adapter yet.
    static let pending = DataSupport(export: .adapterPending, delete: .adapterPending, hold: .userActionsIgnoreHolds)
    /// Native-owned content its owner prunes on its own, without an adapter yet.
    static let pendingPruned = DataSupport(
        export: .adapterPending, delete: .adapterPending, hold: .automaticPruningIgnoresHolds)
    /// Re-fetchable bytes with nothing of the user's: a full removal clears them, and holds don't apply.
    static let cache = DataSupport(export: .notApplicable, delete: .adapterPending, hold: .notApplicable)
    /// Kept by someone else; Native can describe it but not act on it.
    static let outside = DataSupport(export: .outsideNative, delete: .outsideNative, hold: .ownerOutsideNative)
    /// No user data: nothing to export, delete or hold.
    static let none = DataSupport(export: .notApplicable, delete: .notApplicable, hold: .notApplicable)
}

public enum DataSupportLevel: String, Equatable, Sendable {
    /// Native owns it; the adapter that does this is a later integration job.
    case adapterPending
    /// Only its owner outside Native can do this.
    case outsideNative
    /// Nothing of the user's to do it to.
    case notApplicable
}

/// Whether a legal hold can keep a store's records today.
public enum DataHoldSupport: String, Equatable, Sendable {
    /// Native removes records only when the user asks, and those paths don't check holds yet.
    case userActionsIgnoreHolds
    /// Native also prunes records on its own, without checking holds.
    case automaticPruningIgnoresHolds
    /// Its owner can remove records whenever it likes; Native can't keep them.
    case ownerOutsideNative
    /// Not known until the store's schema lands.
    case undetermined
    case notApplicable
}

/// How well the inventory knows the store.
public enum DataIntegrationStatus: Equatable, Sendable {
    /// Its locations and formats were checked against the source at this revision.
    case verified
    /// The code exists, but nothing in production constructs it, so it has no data yet.
    case dormant
    /// Reserved for a store another change is building; its schema and integration aren't known.
    case unknown(String)
}

/// The integration jobs that give stores their adapters, in the order they're meant to land.
public enum DataLifecycleJob: String, CaseIterable, Sendable {
    case hostDatabase = "lifecycle-host-database"
    case search = "lifecycle-search"
    case automation = "lifecycle-automation"
    case appRecords = "lifecycle-app-records"
    case externalAgents = "lifecycle-external-agents"
    case git = "lifecycle-git"
    case secrets = "lifecycle-secrets"
    case remoteHosts = "lifecycle-remote-hosts"
}

/// Who owns a copy and decides what happens to it.
public enum DataOwnership: String, CaseIterable, Codable, Sendable {
    /// Native wrote it and is the only one that uses it.
    case native
    /// An agent's own store; the agent and its provider decide its lifecycle.
    case externalAgent
    /// The user's or organization's own: their repositories, backups, tools and exports.
    case customer
    /// The operating system keeps it (unified logging, crash reports, Notification Center).
    case operatingSystem
    /// Nobody has established who owns it, so nothing may assume Native does.
    case unknown
}

/// What a store can contain, so an administrator can tell transcripts from caches.
public enum DataContentClass: String, CaseIterable, Codable, Comparable, Sendable {
    /// Prompts, transcripts, drafts, outputs and file contents.
    case userContent
    case paths
    case commands
    /// Secret material itself: keys, tokens, passwords.
    case credentials
    /// Ids that point at secrets kept elsewhere.
    case credentialReferences
    /// Opaque ids, device names and other metadata about people or machines.
    case identifiers
    case configuration
    case diagnostics
    case audit
    /// Bytes fetched from elsewhere that can be fetched again.
    case cache

    public static func < (lhs: Self, rhs: Self) -> Bool {
        allCases.firstIndex(of: lhs) ?? 0 < allCases.firstIndex(of: rhs) ?? 0
    }
}
