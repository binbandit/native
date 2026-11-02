import Foundation

/// A host-local file operation carried by the existing command transport. Older hosts reject the
/// reserved executable, so callers can keep the cold worktree rather than fall back to a full copy.
public struct WorktreeClone: Codable, Sendable {
    public static let executable = "_native_clone_worktree_files"

    public let source: URL
    public let destination: URL
    public let paths: [String]
    public let directories: Set<String>

    public init(source: URL, destination: URL, paths: [String], directories: Set<String> = []) {
        self.source = source
        self.destination = destination
        self.paths = paths
        self.directories = directories
    }

    public func command(environment: [String: String]) throws -> Command {
        Command(
            Self.executable, in: source.path(percentEncoded: false), environment: environment,
            standardInput: try JSONEncoder().encode(self))
    }

    public struct Report: Codable, Hashable, Sendable {
        public var cloned: [String] = []
        public var skipped: [String] = []
        public var unsupported = false

        public init() {}
    }
}
