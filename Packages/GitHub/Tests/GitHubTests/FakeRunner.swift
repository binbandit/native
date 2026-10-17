import Exec
import Foundation
import Synchronization

/// Answers gh invocations from a script and records them, so `GitHubCLI` runs end to end without
/// gh, a network or a login.
final class FakeRunner: CommandRunner {
    typealias Script = @Sendable (Command) throws -> CommandResult

    private let script: Script
    private let log = Mutex<[Command]>([])

    init(_ script: @escaping Script) {
        self.script = script
    }

    var commands: [Command] {
        log.withLock { $0 }
    }

    func run(_ command: Command) async throws -> CommandResult {
        log.withLock { $0.append(command) }
        return try script(command)
    }

    static func success(_ data: Data) -> CommandResult {
        CommandResult(exitCode: 0, standardOutput: data, standardError: Data())
    }

    static func failure(_ exitCode: Int32, _ stderr: String) -> CommandResult {
        CommandResult(exitCode: exitCode, standardOutput: Data(), standardError: Data(stderr.utf8))
    }
}
