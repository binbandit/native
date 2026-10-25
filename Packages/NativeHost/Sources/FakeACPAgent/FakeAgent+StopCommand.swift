import ACP
import Foundation

extension FakeAgent {
    /// A cancel reply is not proof the agent's shell stopped. The shell has a separate process
    /// group and ignores TERM, as a command with its own cleanup or background work might. It writes
    /// its pid before `command-ready`, so a test that saw the marker can read the pid.
    func cancelLeavingCommand(_ session: SessionID) async throws -> String {
        let command = Process()
        command.executableURL = URL(filePath: "/bin/sh")
        command.arguments = [
            "-c",
            "trap '' TERM; printf %s $$ > command.pid; printf ready > command-ready; sleep 5; "
                + "printf STOP_COMMAND_FINISHED > stop-marker.txt",
        ]
        command.currentDirectoryURL = store
        command.standardInput = FileHandle.nullDevice
        command.standardOutput = FileHandle.nullDevice
        command.standardError = FileHandle.nullDevice
        try command.run()
        while !cancelled.contains(session), command.isRunning {
            try await Task.sleep(for: .milliseconds(20))
        }
        return cancelled.contains(session) ? "cancelled" : "end_turn"
    }
}
