import Foundation

/// A Native display name, scoped to the machine that owns the folder.
public struct ProjectName: Sendable {
    public let url: URL
    public let customName: String?
    public let scope: String

    public init(url: URL, customName: String? = nil, scope: String = "local") {
        self.url = url.standardizedFileURL
        self.customName = Self.normalized(customName, folderName: url.lastPathComponent)
        self.scope = scope
    }

    public var name: String { customName ?? url.lastPathComponent }

    public static func normalized(_ name: String?, folderName: String) -> String? {
        guard let trimmed = name?.trimmingCharacters(in: .whitespacesAndNewlines),
            !trimmed.isEmpty, trimmed != folderName
        else { return nil }
        return trimmed
    }

    /// Custom names are deliberate. Only unnamed duplicates gain a parent suffix, and a host's
    /// paths are compared with that host's paths rather than this machine's filesystem.
    public static func qualifiers(for projects: [Self]) -> [String?] {
        projects.map { project in
            guard project.customName == nil else { return nil }
            let peers = projects.filter {
                $0.customName == nil && $0.name == project.name && $0.scope == project.scope
                    && $0.url.path != project.url.path
            }
            guard !peers.isEmpty else { return nil }
            let parent = project.url.deletingLastPathComponent().pathComponents
            let others = peers.map { $0.url.deletingLastPathComponent().pathComponents }
            for length in 1...max(1, parent.count) {
                let suffix = parent.suffix(length)
                if others.allSatisfy({ $0.suffix(length) != suffix }) {
                    return suffix.joined(separator: "/").replacingOccurrences(of: "//", with: "/")
                }
            }
            return project.url.deletingLastPathComponent().path
        }
    }
}
