import Foundation
import MCP

/// Read access to the machine whose agents' configuration is being read: this Mac today, a remote
/// Native Host later. Paths are that machine's.
public protocol ConfigFileSystem: Sendable {
    func contents(atPath path: String) -> Data?
    func fileExists(atPath path: String) -> Bool
}

/// This Mac's files.
public struct LocalConfigFiles: ConfigFileSystem {
    public init() {}

    public func contents(atPath path: String) -> Data? {
        FileManager.default.contents(atPath: path)
    }

    public func fileExists(atPath path: String) -> Bool {
        FileManager.default.fileExists(atPath: path)
    }
}

/// Reads configuration files, reporting a problem only when a file exists but can't be read.
struct ConfigFileReader: Sendable {
    let files: any ConfigFileSystem

    func data(at url: URL) -> Data? {
        files.contents(atPath: url.path(percentEncoded: false))
    }

    func exists(_ url: URL) -> Bool {
        files.fileExists(atPath: url.path(percentEncoded: false))
    }

    func json(at url: URL, problems: inout [ConfigProblem]) -> JSON? {
        guard let data = data(at: url) else { return nil }
        do {
            return try JSONDecoder().decode(JSON.self, from: data)
        } catch {
            problems.append(ConfigProblem(file: url, message: "It isn't valid JSON."))
            return nil
        }
    }
}
