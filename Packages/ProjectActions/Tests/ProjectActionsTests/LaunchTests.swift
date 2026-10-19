import Foundation
import Testing

@testable import ProjectActions

struct LaunchTests {
    private let worktree = URL(filePath: "/tmp/wt it's", directoryHint: .isDirectory)
    private let project = URL(filePath: "/tmp/project", directoryHint: .isDirectory)

    @Test func runsInItsDirectoryWithTheEventScriptNames() {
        let action = ProjectAction(name: "Web", command: "bun run dev", directory: .init(base: .project, path: "web"))
        let launch = ProjectActionLaunch(action, worktree: worktree, project: project)
        #expect(launch.directory.path(percentEncoded: false) == "/tmp/project/web/")
        #expect(launch.environment["NATIVE_WORKTREE_PATH"] == "/tmp/wt it's/")
        #expect(launch.environment["NATIVE_PROJECT_PATH"] == "/tmp/project/")
        #expect(launch.environment["NATIVE_ACTION"] == "Web")
    }

    /// The terminal command line, run through `bash -c` the way the terminal runs it, prints the
    /// command, frames it with OSC 133 carrying its exit status, and passes quotes through intact.
    @Test func terminalCommandReportsTheExitStatus() async throws {
        let action = ProjectAction(name: "Quote's", command: #"echo "it's $NATIVE_ACTION"; exit 3"#)
        let launch = ProjectActionLaunch(action, worktree: worktree, project: project)
        let line = launch.terminalCommand(shell: "/bin/sh")

        let process = Process()
        process.executableURL = URL(filePath: "/bin/bash")
        // `-l` and `-i` on /bin/sh read no startup files here (HOME is empty), keeping the test hermetic.
        process.arguments = ["--noprofile", "--norc", "-c", "exec \(line)"]
        process.environment = ["HOME": FileManager.default.temporaryDirectory.path, "PATH": "/usr/bin:/bin"]
        let output = Pipe()
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        process.standardInput = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()
        let text = String(decoding: output.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)

        #expect(process.terminationStatus == 3)
        #expect(text.contains("\u{1B}[2m$ \(action.command)\u{1B}[0m\n"))
        #expect(text.contains("\u{1B}]133;C\u{07}it's Quote's\n\u{1B}]133;D;3\u{07}"))
    }
}
