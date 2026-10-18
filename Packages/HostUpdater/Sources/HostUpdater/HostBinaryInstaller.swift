import Foundation

#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

/// Installs `native-host` builds side by side and switches between them atomically, with a ledger
/// that rolls back a build that never comes up healthy. The supervisor (launchd or systemd) always
/// runs `<root>/native-host`, a symlink into `<root>/versions/<build>/`:
///
///     stage(_:asset:build:)   download verified and written; nothing changes yet
///     activate(build:)        the symlink moves; the host exits 75 and its supervisor starts the build
///     startupCheck(…)         first thing at launch: counts unconfirmed launches, rolls back after two
///     confirm(runningBuild:)  the new host is serving and passed its own handshake
public struct HostBinaryInstaller: Sendable {
    public enum StartupDecision: Equatable, Sendable {
        case normal
        /// A newly activated build, on its `attempt`th launch; call `confirm` once it serves.
        case trial(attempt: Int)
        /// The candidate kept failing, so the symlink points back at `to`. Exit (status 75) so the
        /// supervisor starts it.
        case rolledBack(from: String, to: String)
    }

    /// Launches a candidate gets to confirm itself before it's rolled back.
    public static let maxUnconfirmedLaunches = 2

    public let root: URL
    private let key: UpdateSigningKey

    public init(root: URL, key: UpdateSigningKey) {
        self.root = root
        self.key = key
    }

    /// What the supervisor runs.
    public var executable: URL { root.appending(path: "native-host") }

    private var versions: URL { root.appending(path: "versions", directoryHint: .isDirectory) }
    private var ledgerURL: URL { root.appending(path: "update-ledger.json") }

    private func binary(_ build: String) -> URL {
        versions.appending(path: "\(build)/native-host")
    }

    // MARK: - Installing

    /// Verifies a downloaded binary against its feed entry and writes it beside the others. What
    /// runs doesn't change.
    public func stage(_ data: Data, asset: HostUpdateFeed.Asset, build: String) throws {
        guard data.count == asset.size else { throw HostUpdateError.sizeMismatch }
        guard UpdateSigningKey.sha256(data) == asset.sha256.lowercased() else { throw HostUpdateError.checksumMismatch }
        guard key.isValidSignature(asset.edSignature, for: data) else {
            throw HostUpdateError.badSignature("the downloaded host")
        }
        let destination = binary(build)
        try FileManager.default.createDirectory(
            at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: destination, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: destination.path)
    }

    public func isStaged(_ build: String) -> Bool {
        FileManager.default.isExecutableFile(atPath: binary(build).path)
    }

    /// Points the supervisor at a staged build and records it as the candidate.
    public func activate(build: String) throws {
        guard isStaged(build) else { throw HostUpdateError.notStaged(build: build) }
        var ledger = ledger()
        if ledger.current == nil, let running = currentTarget() {
            ledger.current = running
        }
        try point(at: build)
        ledger.candidate = build
        ledger.candidateLaunches = 0
        try save(ledger)
    }

    // MARK: - Starting up

    public func startupCheck(runningBuild: String) throws -> StartupDecision {
        var ledger = ledger()
        guard let candidate = ledger.candidate, candidate == runningBuild else { return .normal }
        ledger.candidateLaunches += 1
        if ledger.candidateLaunches > Self.maxUnconfirmedLaunches, let good = ledger.current, isStaged(good) {
            try point(at: good)
            ledger.candidate = nil
            ledger.candidateLaunches = 0
            ledger.lastRollback = .init(from: candidate, to: good, at: .now)
            try save(ledger)
            return .rolledBack(from: candidate, to: good)
        }
        try save(ledger)
        return .trial(attempt: ledger.candidateLaunches)
    }

    /// Makes the running build the known-good one and removes builds older than the one before it.
    public func confirm(runningBuild: String) throws {
        var ledger = ledger()
        guard ledger.candidate == runningBuild else { return }
        ledger.previous = ledger.current
        ledger.current = runningBuild
        ledger.candidate = nil
        ledger.candidateLaunches = 0
        try save(ledger)
        let keep = Set([ledger.current, ledger.previous].compactMap(\.self))
        let builds = (try? FileManager.default.contentsOfDirectory(atPath: versions.path)) ?? []
        for build in builds where !keep.contains(build) {
            try? FileManager.default.removeItem(at: versions.appending(path: build))
        }
    }

    // MARK: - Ledger

    public func ledger() -> HostUpdateLedger {
        guard let data = try? Data(contentsOf: ledgerURL) else { return HostUpdateLedger() }
        return (try? JSONDecoder.ledger.decode(HostUpdateLedger.self, from: data)) ?? HostUpdateLedger()
    }

    private func save(_ ledger: HostUpdateLedger) throws {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try JSONEncoder.ledger.encode(ledger).write(to: ledgerURL, options: .atomic)
    }

    // MARK: - The symlink

    /// The build `native-host` points at now.
    private func currentTarget() -> String? {
        guard let target = try? FileManager.default.destinationOfSymbolicLink(atPath: executable.path) else { return nil }
        let parts = target.split(separator: "/")
        return parts.count >= 2 ? String(parts[parts.count - 2]) : nil
    }

    /// Swaps the symlink with `rename(2)`, so the supervisor sees the old build or the new one,
    /// never a missing file.
    private func point(at build: String) throws {
        let staging = root.appending(path: "native-host.next")
        try? FileManager.default.removeItem(at: staging)
        try FileManager.default.createSymbolicLink(atPath: staging.path, withDestinationPath: "versions/\(build)/native-host")
        guard rename(staging.path, executable.path) == 0 else {
            throw CocoaError(.fileWriteUnknown, userInfo: [NSFilePathErrorKey: executable.path])
        }
    }
}

/// What the installer remembers between launches, in `<root>/update-ledger.json`.
public struct HostUpdateLedger: Codable, Equatable, Sendable {
    public struct Rollback: Codable, Equatable, Sendable {
        public var from: String
        public var to: String
        public var at: Date
    }

    /// The last build that came up healthy.
    public var current: String?
    /// The one before it, kept for a rollback.
    public var previous: String?
    /// Activated but not yet confirmed.
    public var candidate: String?
    public var candidateLaunches = 0
    /// The last automatic rollback, for the update status and the activity journal.
    public var lastRollback: Rollback?

    public init() {}
}

extension JSONDecoder {
    fileprivate static let ledger: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()
}

extension JSONEncoder {
    fileprivate static let ledger: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }()
}
