import Foundation

/// Project-owned choices. Folder names match ignored directories at any depth; paths containing
/// a slash select that exact project-relative folder. Environment files always require consent.
public struct WorktreeWarmSettings: Codable, Hashable, Sendable {
    public static let commonFolders = [
        "node_modules", ".venv", ".build", "target", "Pods", "DerivedData", ".next", "dist",
    ]

    public var enabled: Bool
    public var folders: [String]
    public var includesEnvironmentFiles: Bool

    public init(enabled: Bool = true, folders: [String] = Self.commonFolders, includesEnvironmentFiles: Bool = false) {
        self.enabled = enabled
        self.folders = folders
        self.includesEnvironmentFiles = includesEnvironmentFiles
    }

    public static func isValidFolder(_ path: String) -> Bool {
        !path.isEmpty && !path.hasPrefix("/") && !path.contains(where: { $0.isNewline || $0 == "\0" })
            && !path.split(separator: "/", omittingEmptySubsequences: false).contains {
                $0.isEmpty || $0 == "." || $0 == ".." || $0 == ".git" || $0.hasPrefix(".env")
            }
    }

    func matches(_ path: String) -> Bool {
        folders.filter(Self.isValidFolder).contains { folder in
            folder.contains("/") ? path == folder : path.split(separator: "/").last.map(String.init) == folder
        }
    }
}
