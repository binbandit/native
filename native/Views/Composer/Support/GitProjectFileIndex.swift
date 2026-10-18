#if os(macOS)
import Foundation

/// A local project's files from git: tracked and untracked ones, without what .gitignore excludes,
/// which stays fast on large repositories. Outside a repository it has no files to offer.
nonisolated struct GitProjectFileIndex: ProjectFileIndex {
    let root: URL

    @concurrent
    func files() async throws -> [String] {
        try Self.git(["ls-files", "-z", "--cached", "--others", "--exclude-standard"], in: root)
            .split(separator: "\0")
            .map(String.init)
    }

    @concurrent
    func changedFiles() async -> Set<String> {
        // Porcelain -z: "XY path\0", with a rename's original path as an extra entry.
        guard let output = try? Self.git(["status", "--porcelain", "-z", "--untracked-files=all"], in: root) else {
            return []
        }
        return Set(
            output.split(separator: "\0").compactMap { entry in
                entry.count > 3 ? String(entry.dropFirst(3)) : nil
            })
    }

    private static func git(_ arguments: [String], in folder: URL) throws -> String {
        let process = Process()
        process.executableURL = URL(filePath: "/usr/bin/git")
        process.arguments = ["-C", folder.path(percentEncoded: false)] + arguments
        let output = Pipe()
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        try process.run()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return String(decoding: data, as: UTF8.self)
    }
}
#endif
