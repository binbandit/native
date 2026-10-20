import Foundation
import Synchronization

#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

/// A key the host keeps for one of an agent's sign-in methods (docs/agents.md, "Signing in on a
/// host with no screen"). It never leaves the host: not in logs, the journal, or anything sent to
/// clients, which only learn which methods have one (`HostAgent.savedCredentials`).
public struct HostCredential: Codable, Hashable, Sendable {
    public var agentID: String
    public var methodID: String
    /// The variable the agent starts with it in, for an `environment` method; nil for a key the
    /// agent takes in `authenticate`.
    public var variable: String?
    public var secret: String

    public init(agentID: String, methodID: String, variable: String?, secret: String) {
        self.agentID = agentID
        self.methodID = methodID
        self.variable = variable
        self.secret = secret
    }
}

extension HostCredential: CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable {
    public var description: String {
        "HostCredential(\(agentID)/\(methodID)\(variable.map { " in \($0)" } ?? ""), secret: <redacted>)"
    }

    public var debugDescription: String { description }

    public var customMirror: Mirror {
        Mirror(self, children: ["agentID": agentID, "methodID": methodID, "variable": variable as Any])
    }
}

/// Where the host keeps agents' keys: the login keychain on a Mac (`HostKeychain` in NativeHostMac),
/// or `HostCredentialFile` anywhere else.
public protocol HostCredentialStore: Sendable {
    func load() throws -> [HostCredential]
    /// Saves `credential`, replacing the one for the same agent and method.
    func save(_ credential: HostCredential) throws
    func remove(agentID: String, methodID: String) throws
}

/// The portable store: `credentials.json` in the host's directory, readable and writable by this
/// user only (the file is 0600, the directory 0700). It's as safe as the user's account: anything
/// running as the user can read it, as it can the agents' own login files. Writes go to a new
/// 0600 file that replaces the old one, so a crash never leaves half a file.
public struct HostCredentialFile: HostCredentialStore {
    public let url: URL

    public init(directory: URL) {
        url = directory.appending(path: "credentials.json")
    }

    public func load() throws -> [HostCredential] {
        guard FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) else { return [] }
        return try JSONDecoder().decode([HostCredential].self, from: Data(contentsOf: url))
    }

    public func save(_ credential: HostCredential) throws {
        var credentials = try load().filter {
            !($0.agentID == credential.agentID && $0.methodID == credential.methodID)
        }
        credentials.append(credential)
        try replace(with: credentials)
    }

    public func remove(agentID: String, methodID: String) throws {
        let credentials = try load()
        let kept = credentials.filter { !($0.agentID == agentID && $0.methodID == methodID) }
        guard kept.count != credentials.count else { return }
        try replace(with: kept)
    }

    private func replace(with credentials: [HostCredential]) throws {
        let data = try JSONEncoder().encode(credentials)
        let path = url.path(percentEncoded: false)
        let temporary = path + ".\(UUID().uuidString).tmp"
        let descriptor = open(temporary, O_WRONLY | O_CREAT | O_EXCL | O_CLOEXEC, 0o600)
        guard descriptor >= 0 else { throw Failure(operation: "create", code: errno) }
        let written = data.withUnsafeBytes { bytes in write(descriptor, bytes.baseAddress, bytes.count) }
        let synced = fsync(descriptor)
        close(descriptor)
        guard written == data.count, synced == 0, rename(temporary, path) == 0 else {
            let code = errno
            unlink(temporary)
            throw Failure(operation: "write", code: code)
        }
    }

    struct Failure: Error, LocalizedError {
        var operation: String
        var code: Int32

        var errorDescription: String? {
            "Couldn't \(operation) the host's saved keys: \(String(cString: strerror(code)))."
        }
    }
}

/// The host's keys, read from its store once and kept in memory after.
public final class HostCredentials: Sendable {
    private let store: any HostCredentialStore
    private let cache = Mutex<[HostCredential]?>(nil)

    public init(store: any HostCredentialStore) {
        self.store = store
    }

    public func all() throws -> [HostCredential] {
        try cache.withLock { cache in
            if let cache { return cache }
            let loaded = try store.load()
            cache = loaded
            return loaded
        }
    }

    public func saved(for agentID: String) throws -> [HostCredential] {
        try all().filter { $0.agentID == agentID }
    }

    public func save(_ credential: HostCredential) throws {
        try cache.withLock { cache in
            try store.save(credential)
            cache = nil
        }
    }

    public func remove(agentID: String, methodID: String) throws {
        try cache.withLock { cache in
            try store.remove(agentID: agentID, methodID: methodID)
            cache = nil
        }
    }
}
