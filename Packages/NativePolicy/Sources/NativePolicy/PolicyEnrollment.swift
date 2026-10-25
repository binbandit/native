import Foundation

/// A restricted deployment mode the organization once set. It keeps Native restricted, with
/// everything optional denied, when the managed policy later disappears or can't be read, until the
/// organization deploys `policy.deployment.mode` = `ordinary` itself. Removing a profile is not that
/// transition; neither is any user setting.
public struct PolicyEnrollment: Codable, Equatable, Sendable {
    public var mode: NativePolicy.DeploymentMode
    /// The revision that last confirmed the mode.
    public var revision: PolicyRevision?

    public init(mode: NativePolicy.DeploymentMode, revision: PolicyRevision?) {
        self.mode = mode
        self.revision = revision
    }
}

/// Where a restricted enrollment outlives the process. Only the loader writes it, from the
/// organization's own input.
public protocol PolicyEnrollmentStore: Sendable {
    func load() -> PolicyEnrollment?
    /// Records the enrollment, or forgets it when the organization deploys ordinary mode. Throws
    /// when it can't be kept across a restart.
    func save(_ enrollment: PolicyEnrollment?) throws
}

/// Keeps the enrollment in a file of its own, outside the preferences policy keys are read from.
public final class FilePolicyEnrollmentStore: PolicyEnrollmentStore, @unchecked Sendable {
    private let url: URL
    private let lock = NSLock()
    // Read once: policy loads on every preference change, and only this store writes the file.
    // An enrollment that couldn't be written is held here instead, so it holds until Native quits.
    private var cached: PolicyEnrollment??
    /// The cache is ahead of the file because a write failed, so the next save tries again.
    private var isUnwritten = false

    public init(url: URL) {
        self.url = url
    }

    public func load() -> PolicyEnrollment? {
        lock.withLock {
            if let cached { return cached }
            // An unreadable record still means an enrollment was made; airGapped is the safe reading.
            let stored: PolicyEnrollment? =
                FileManager.default.fileExists(atPath: url.path(percentEncoded: false))
                ? (try? Data(contentsOf: url)).flatMap { try? JSONDecoder().decode(PolicyEnrollment.self, from: $0) }
                    ?? PolicyEnrollment(mode: .airGapped, revision: nil)
                : nil
            cached = .some(stored)
            return stored
        }
    }

    public func save(_ enrollment: PolicyEnrollment?) throws {
        try lock.withLock {
            if !isUnwritten, case .some(let current) = cached, current == enrollment { return }
            do {
                if let enrollment {
                    try FileManager.default.createDirectory(
                        at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
                    try JSONEncoder().encode(enrollment).write(to: url, options: .atomic)
                } else if FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) {
                    try FileManager.default.removeItem(at: url)
                }
                cached = .some(enrollment)
                isUnwritten = false
            } catch {
                // A restriction stays in memory. A release that couldn't remove the file leaves the
                // cache unset, so the next load reads the restriction the file still holds.
                cached = enrollment.map { .some($0) }
                isUnwritten = enrollment != nil
                throw error
            }
        }
    }
}

/// An enrollment held in memory, for tests and harnesses that stand in for a restart.
public final class MemoryPolicyEnrollmentStore: PolicyEnrollmentStore, @unchecked Sendable {
    private let lock = NSLock()
    private var stored: PolicyEnrollment?

    public init(_ enrollment: PolicyEnrollment? = nil) {
        stored = enrollment
    }

    public func load() -> PolicyEnrollment? { lock.withLock { stored } }
    public func save(_ enrollment: PolicyEnrollment?) { lock.withLock { stored = enrollment } }
}
