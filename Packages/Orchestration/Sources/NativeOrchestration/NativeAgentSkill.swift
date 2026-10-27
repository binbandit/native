import Foundation

/// Installs only Native-owned copies. A collision or a user edit leaves every existing byte alone.
public enum NativeAgentSkill {
    public static let name = "native-app"
    private static let receipt = ".native-install.json"
    private static let resources = ["SKILL.md", "references/tasks.md", "references/setup.md", "references/scripts.md"]

    public static func files(cli: String) throws -> [String: Data] {
        guard let root = Bundle.module.url(forResource: name, withExtension: nil) else { throw Failure.resources }
        var files: [String: Data] = [:]
        for path in resources { files[path] = try Data(contentsOf: root.appending(path: path)) }
        let quoted = "'" + cli.replacingOccurrences(of: "'", with: "'\\''") + "'"
        // Codex can share this installation across Native channels. Its task's host wins over the
        // installation's fallback path, so another channel cannot redirect an already running task.
        files["scripts/native"] = Data(
            ("#!/bin/sh\nnative_cli=${NATIVE_ACTION_CLI:-" + quoted + "}\nexec \"$native_cli\" action \"$@\"\n").utf8)
        return files
    }

    @discardableResult
    public static func install(at directory: URL, cli: String) throws -> URL {
        let manager = FileManager.default
        let files = try files(cli: cli)
        if manager.fileExists(atPath: directory.path) {
            let values = try directory.resourceValues(forKeys: [.isSymbolicLinkKey, .isDirectoryKey])
            guard values.isSymbolicLink != true, values.isDirectory == true,
                let data = try? Data(contentsOf: directory.appending(path: receipt)),
                let previous = try? JSONDecoder().decode([String: Data].self, from: data),
                try contents(directory) == previous
            else { throw Failure.userOwned }
            if previous == files { return directory }
        }
        let parent = directory.deletingLastPathComponent()
        try manager.createDirectory(at: parent, withIntermediateDirectories: true)
        let stage = parent.appending(path: ".native-stage-" + UUID().uuidString)
        let backup = parent.appending(path: ".native-backup-" + UUID().uuidString)
        defer { try? manager.removeItem(at: stage) }
        try manager.createDirectory(at: stage, withIntermediateDirectories: false)
        for (path, data) in files {
            let target = stage.appending(path: path)
            try manager.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: target)
        }
        try manager.setAttributes(
            [.posixPermissions: 0o755], ofItemAtPath: stage.appending(path: "scripts/native").path)
        try JSONEncoder().encode(files).write(to: stage.appending(path: receipt))
        let existed = manager.fileExists(atPath: directory.path)
        if existed { try manager.moveItem(at: directory, to: backup) }
        do {
            try manager.moveItem(at: stage, to: directory)
        } catch {
            if existed { try? manager.moveItem(at: backup, to: directory) }
            throw error
        }
        if existed { try manager.removeItem(at: backup) }
        return directory
    }

    private static func contents(_ root: URL) throws -> [String: Data] {
        let manager = FileManager.default
        let root = root.resolvingSymlinksInPath()
        guard
            let entries = manager.enumerator(
                at: root, includingPropertiesForKeys: [.isSymbolicLinkKey, .isDirectoryKey])
        else { throw Failure.userOwned }
        var result: [String: Data] = [:]
        for case let file as URL in entries {
            let values = try file.resourceValues(forKeys: [.isSymbolicLinkKey, .isDirectoryKey])
            guard values.isSymbolicLink != true else { throw Failure.userOwned }
            if values.isDirectory == true { continue }
            let path = String(file.resolvingSymlinksInPath().path.dropFirst(root.path.count + 1))
            if path != receipt { result[path] = try Data(contentsOf: file) }
        }
        return result
    }

    public enum Failure: Error, LocalizedError {
        case resources, userOwned
        public var errorDescription: String? {
            switch self {
            case .resources: "Native's bundled skill is unavailable."
            case .userOwned: "The native-app skill already exists or was edited. Native left it unchanged and uses MCP."
            }
        }
    }
}
