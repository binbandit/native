import Foundation

/// What a store's owner reports about one record, without its content. The planner believes only
/// what's here: it never looks a path up, follows a link or decides ownership from where something is.
public struct DataRecord: Equatable, Codable, Sendable {
    public var key: DataRecordKey
    /// The larger records it belongs to (its project, the task that started it). A request or a hold
    /// naming one of them covers this record too.
    public var parents: Set<DataRecordKey>
    /// Every time the owner knows for the record (created, last active). The newest sets its age;
    /// none means its age is unknown.
    public var timestamps: [Date]
    public var copies: [DataRecordCopy]

    public init(
        _ key: DataRecordKey, parents: Set<DataRecordKey> = [], timestamps: [Date] = [], copies: [DataRecordCopy]
    ) {
        self.key = key
        self.parents = parents
        self.timestamps = timestamps
        self.copies = copies
    }

    /// The keys a request or a hold can name it by.
    var keys: Set<DataRecordKey> { parents.union([key]) }
}

/// One copy of a record, as its owner sees it.
public struct DataRecordCopy: Equatable, Codable, Sendable {
    public var kind: DataCopyKind
    /// Where it is, under one of the caller's roots. Copies kept in preferences, the Keychain or git
    /// refs have none.
    public var location: DataRelativePath?
    /// Who the owner says it belongs to.
    public var ownership: DataOwnership
    public var link: DataLinkState
    public var availability: DataAvailability
    /// Other records using the same copy (a folder two tasks share). It goes only when all of them do.
    public var sharedWith: Set<DataRecordKey>

    public init(
        _ kind: DataCopyKind, at location: DataRelativePath? = nil, ownership: DataOwnership = .native,
        link: DataLinkState = .regular, availability: DataAvailability = .local, sharedWith: Set<DataRecordKey> = []
    ) {
        self.kind = kind
        self.location = location
        self.ownership = ownership
        self.link = link
        self.availability = availability
        self.sharedWith = sharedWith
    }
}

/// What the owner found at the copy's path when it listed it.
public enum DataLinkState: String, Codable, Sendable {
    case regular
    /// A symbolic link, or a path with one in it: removing it could reach somewhere else.
    case symbolicLink
    case unknown
}

public enum DataAvailability: String, Codable, Sendable {
    case local
    /// On a paired host that is connected now.
    case remoteOnline
    case remoteOffline
    case unknown
}

/// What one store's owner listed for a request.
public enum DataStoreReport: Equatable, Sendable {
    /// Every record the store holds that could be in scope, possibly none.
    case listed([DataRecord])
    /// The owner couldn't list its records.
    case unavailable
}
