import ACP
import Foundation
import TaskList

/// A catalog bucket, never an opened project. It lets all existing task operations share the same
/// ordering and durable catalog without registering Native's private storage as a user folder.
enum NoProjectLocation {
    static let id = UUID(
        uuid: (
            0xCA, 0x71, 0x10, 0xCE, 0xE3, 0x50, 0x41, 0xD4,
            0x89, 0x08, 0x16, 0xD9, 0x72, 0xB8, 0x0F, 0x1A
        ))
    static var root: URL {
        URL.applicationSupportDirectory.standardizedFileURL.resolvingSymlinksInPath().appendingPathComponent(
            Bundle.main.bundleIdentifier ?? "Native", isDirectory: true
        )
        .appendingPathComponent("Task Files", isDirectory: true).standardizedFileURL
    }
    static var group: Project { Project(id: id, url: root, displayName: "No project") }
    static func contains(_ folder: URL) -> Bool {
        let path = folder.standardizedFileURL.path
        return path.hasPrefix(root.path + "/")
    }
    static func key(_ key: SessionKey) -> String { "\(key.agent.rawValue)/\(key.id.rawValue)" }
}

extension Project {
    var isNoProject: Bool { id == NoProjectLocation.id }
}

extension SessionModel {
    var isProjectless: Bool {
        services.isProjectlessTask(key) || cwd.standardizedFileURL.path.hasPrefix(services.scratchRoot.path + "/")
    }
}
