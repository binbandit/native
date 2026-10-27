import Foundation

/// Native-owned working folders. Catalog membership is separate from project membership so a
/// moved task keeps its original files until deletion. Only direct, non-linked children are owned.
@MainActor
public final class TaskScratchStore {
    public enum Failure: LocalizedError {
        case unsafeFolder, invalidDestination

        public var errorDescription: String? {
            switch self {
            case .unsafeFolder: "The private task folder is unavailable. Nothing was removed."
            case .invalidDestination: "Choose a project folder outside Native's private task files."
            }
        }
    }

    public let root: URL
    private let index: URL
    private var folders: [String: UUID]
    private let persists: Bool

    public init(root: URL, persists: Bool = true) {
        self.persists = persists
        self.root = root.standardizedFileURL
        index = root.appendingPathComponent("tasks.json")
        folders =
            (try? Data(contentsOf: index)).flatMap {
                try? JSONDecoder().decode([String: UUID].self, from: $0)
            } ?? [:]
    }

    /// Allocated before agent startup; a retry uses the same directory.
    public func create(for task: String) throws -> URL {
        if let folder = folder(for: task) {
            guard owns(folder) else { throw Failure.unsafeFolder }
            return folder
        }
        let id = UUID()
        let folder = root.appendingPathComponent(id.uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: folder, withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700])
        folders[task] = id
        do { try save() } catch {
            folders[task] = nil
            try? FileManager.default.removeItem(at: folder)
            throw error
        }
        return folder
    }

    public func folder(for task: String) -> URL? {
        folders[task].map { root.appendingPathComponent($0.uuidString, isDirectory: true) }
    }

    /// Publish the transport's permanent identity only after the agent created the conversation.
    public func transfer(from old: String, to new: String) throws {
        guard let id = folders[old] else { return }
        let previous = folders
        folders[old] = nil
        folders[new] = id
        do { try save() } catch { folders = previous; throw error }
    }

    /// Conversation replacements keep the same logical task and working folder.
    public func reassign(_ folder: URL, to task: String) throws {
        guard owns(folder), let id = UUID(uuidString: folder.lastPathComponent) else { throw Failure.unsafeFolder }
        let previous = folders
        folders = folders.filter { $0.value != id }
        folders[task] = id
        do { try save() } catch { folders = previous; throw error }
    }

    public func owns(_ folder: URL) -> Bool {
        let plain = folder.standardizedFileURL
        guard plain.deletingLastPathComponent() == root,
            UUID(uuidString: plain.lastPathComponent) != nil,
            folders.values.contains(where: { $0.uuidString == plain.lastPathComponent }),
            plain.resolvingSymlinksInPath() == plain,
            root.resolvingSymlinksInPath() == root
        else { return false }
        return true
    }

    /// Archive deliberately has no filesystem operation. Delete is called after the Undo window
    /// and after closing the agent, never while that agent can still write into its folder.
    public func delete(_ task: String) throws {
        guard let folder = folder(for: task) else { return }
        guard owns(folder) else { throw Failure.unsafeFolder }
        if FileManager.default.fileExists(atPath: folder.path) { try FileManager.default.removeItem(at: folder) }
        let previous = folders
        folders = folders.filter { $0.value.uuidString != folder.lastPathComponent }
        do { try save() } catch { folders = previous; throw error }
    }

    /// A unique child prevents collisions, partial overwrites and merging into existing files.
    /// The source stays owned until deletion, including after a successful project move.
    public func copyFiles(of task: String, into project: URL) throws -> URL? {
        try copyingFiles(of: task, into: project)()
    }

    /// Snapshot ownership on the model's actor, then run bulk I/O away from the interface thread.
    public func copyingFiles(of task: String, into project: URL) throws -> @Sendable () throws -> URL? {
        guard let source = folder(for: task), owns(source) else { throw Failure.unsafeFolder }
        let root = root
        return { try Self.copyFiles(from: source, into: project, root: root) }
    }

    private nonisolated static func copyFiles(from source: URL, into project: URL, root: URL) throws -> URL? {
        guard source.resolvingSymlinksInPath() == source, root.resolvingSymlinksInPath() == root else {
            throw Failure.unsafeFolder
        }
        let target = project.standardizedFileURL.resolvingSymlinksInPath()
        guard target != root, !target.path.hasPrefix(root.path + "/"),
            (try? target.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
        else { throw Failure.invalidDestination }
        let children = try FileManager.default.contentsOfDirectory(at: source, includingPropertiesForKeys: nil)
        guard !children.isEmpty else { return nil }
        let destination = target.appendingPathComponent("Task Files \(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: false)
        do {
            for child in children {
                // Copy the link itself, never traverse it into user-owned files.
                try FileManager.default.copyItem(
                    at: child, to: destination.appendingPathComponent(child.lastPathComponent))
            }
            return destination
        } catch {
            try? FileManager.default.removeItem(at: destination)
            throw error
        }
    }

    private func save() throws {
        guard persists else { return }
        try FileManager.default.createDirectory(
            at: root, withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700])
        try JSONEncoder().encode(folders).write(to: index, options: .atomic)
    }
}
