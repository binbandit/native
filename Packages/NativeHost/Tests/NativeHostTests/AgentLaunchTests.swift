import ACP
import Foundation
import Testing

@testable import NativeHost

struct AgentLaunchTests {
    /// A process started by something other than `Process` inherits every descriptor that isn't
    /// close-on-exec (some terminals start their shell this way). The channel's copy of the agent's
    /// input wasn't, so such a process held it open, and the agent never saw it end when the channel
    /// closed.
    @Test func agentSeesItsInputEndEvenIfAnotherProcessStartedMeanwhile() async throws {
        // `cat` stands in for an agent: it exits once its input ends.
        let command = AgentCommand(executable: "cat", environment: ["PATH": "/usr/bin:/bin"])
        let (process, channel, _) = try AgentLaunch.spawn(command)
        defer { if process.isRunning { process.terminate() } }
        let inheritor = try spawnInheritingDescriptors()
        defer { reap(inheritor) }
        channel.close()
        let clock = ContinuousClock()
        let start = clock.now
        while process.isRunning, clock.now - start < .seconds(10) {
            try await Task.sleep(for: .milliseconds(20))
        }
        #expect(!process.isRunning)
    }

    /// Starts `sleep 30` inheriting every descriptor that isn't close-on-exec.
    private func spawnInheritingDescriptors() throws -> pid_t {
        var pid: pid_t = 0
        let words: [String] = ["/bin/sleep", "30"]
        let arguments = words.map { strdup($0) }
        defer { arguments.forEach { free($0) } }
        let status = posix_spawn(&pid, "/bin/sleep", nil, nil, arguments + [nil], [nil])
        guard status == 0 else { throw POSIXError(POSIXErrorCode(rawValue: status) ?? .EINVAL) }
        return pid
    }

    private func reap(_ pid: pid_t) {
        kill(pid, SIGKILL)
        waitpid(pid, nil, 0)
    }
}
