#if os(macOS)
import Foundation
import Testing

/// Every test in the package, run one at a time. The stress tests saturate the machine, and the
/// others time commands, so run alongside them on a small CI runner the timeouts fired seconds late.
/// Time limits in the tests sit well clear of the slow path they rule out (a 30-second sleep, say).
@Suite(.serialized) struct ExecTests {
    static let environment = ["PATH": "/usr/bin:/bin"]

    /// Starts a process the way a spawner that doesn't close what it didn't open would (some
    /// terminals start their shell this way): it inherits every descriptor that isn't close-on-exec.
    /// Kill and reap it with `reap(_:)`.
    static func spawnInheritingDescriptors() throws -> pid_t {
        var pid: pid_t = 0
        let words: [String] = ["/bin/sleep", "30"]
        let arguments = words.map { strdup($0) }
        defer { arguments.forEach { free($0) } }
        let status = posix_spawn(&pid, "/bin/sleep", nil, nil, arguments + [nil], [nil])
        guard status == 0 else { throw POSIXError(POSIXErrorCode(rawValue: status) ?? .EINVAL) }
        return pid
    }

    static func reap(_ pid: pid_t) {
        kill(pid, SIGKILL)
        waitpid(pid, nil, 0)
    }

    /// A path for a command to wait on, so a test can let it go on at the right moment.
    static func flagPath() -> String {
        FileManager.default.temporaryDirectory.appending(path: "exec-test-\(UUID().uuidString)")
            .path(percentEncoded: false)
    }
}
#endif
