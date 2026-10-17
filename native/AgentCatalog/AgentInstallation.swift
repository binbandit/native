import Foundation

/// Whether an agent can run on this machine: its command and the CLIs it `requires` are all on the
/// user's PATH. Checked before an agent is started, so one that isn't installed is offered in Add
/// Agent instead of appearing as a broken agent.
nonisolated struct AgentInstallation: Equatable, Sendable {
    /// The first command the agent needs that isn't on the PATH; nil when it has everything.
    let missingCommand: String?

    var isInstalled: Bool {
        missingCommand == nil
    }

    init(_ manifest: AgentManifest, environment: [String: String]) {
        // The CLI an adapter drives is the meaningful one to name; `npx` comes with Node.
        missingCommand = (manifest.requires + [manifest.command]).first { Self.locate($0, in: environment) == nil }
    }

    /// Where `command` resolves the way the agent's process will run it: an absolute path, or the
    /// first match on the environment's PATH.
    static func locate(_ command: String, in environment: [String: String]) -> String? {
        let fileManager = FileManager.default
        if command.hasPrefix("/") {
            return fileManager.isExecutableFile(atPath: command) ? command : nil
        }
        return environment["PATH", default: ""].split(separator: ":").lazy
            .map { URL(filePath: String($0)).appending(path: command).path(percentEncoded: false) }
            .first { fileManager.isExecutableFile(atPath: $0) }
    }
}
