#if os(macOS)
import Exec
import Foundation
import NativeHostProtocol
import Synchronization
import Testing

@testable import NativeHostClient

@Suite("Development host launchd job")
struct LaunchdSessionJobTests {
    let root = FileManager.default.temporaryDirectory.appending(
        path: "launchd-job-\(UUID().uuidString.prefix(8))", directoryHint: .isDirectory)

    /// A plist like the one `install-launch-agent.sh` generates.
    private func bundledPlist() throws -> URL {
        let plist: [String: Any] = [
            "Label": "app.native.host.0123456789",
            "BundleProgram": "Contents/Library/LoginItems/Native Host.app/Contents/MacOS/Native Host",
            "AssociatedBundleIdentifiers": ["app.native"],
            "KeepAlive": ["SuccessfulExit": false],
            "EnvironmentVariables": ["NATIVE_HOST_CHANNEL": "0123456789"],
        ]
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let url = root.appending(path: "NativeHost.plist")
        try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0).write(to: url)
        return url
    }

    @Test("The session job runs the helper by absolute path and isn't tied to the app as a login item")
    func plist() throws {
        let job = LaunchdSessionJob(
            bundledPlist: try bundledPlist(), appBundle: URL(filePath: "/Builds/Native.app"),
            location: HostLocation(directory: root.appending(path: "host"), channel: "0123456789")
        )
        let (label, plist) = try job.sessionPlist()
        #expect(label == "app.native.host.0123456789")
        #expect(
            plist["Program"] as? String
                == "/Builds/Native.app/Contents/Library/LoginItems/Native Host.app/Contents/MacOS/Native Host")
        #expect(plist["BundleProgram"] == nil)
        #expect(plist["AssociatedBundleIdentifiers"] == nil)
        #expect((plist["EnvironmentVariables"] as? [String: String])?["NATIVE_HOST_CHANNEL"] == "0123456789")
    }

    @Test("Starting re-enables the label, loads the job for this session and makes sure it runs")
    func startCommands() async throws {
        let runner = RecordingRunner()
        let location = HostLocation(directory: root.appending(path: "host"), channel: "0123456789")
        let job = LaunchdSessionJob(
            bundledPlist: try bundledPlist(), appBundle: URL(filePath: "/Builds/Native.app"), location: location,
            runner: runner)
        try await job.start()
        let domain = "gui/\(getuid())"
        #expect(
            runner.commands == [
                ["enable", "\(domain)/app.native.host.0123456789"],
                ["bootstrap", domain, location.directory.appending(path: "launchd.plist").path(percentEncoded: false)],
                ["kickstart", "\(domain)/app.native.host.0123456789"],
            ])
        #expect(
            FileManager.default.fileExists(
                atPath: location.directory.appending(path: "launchd.plist").path(percentEncoded: false)))
        try await job.stop()
        #expect(runner.commands.last == ["bootout", "\(domain)/app.native.host.0123456789"])
    }
}

private final class RecordingRunner: CommandRunner {
    private let recorded = Mutex<[[String]]>([])

    var commands: [[String]] {
        recorded.withLock { $0 }
    }

    func run(_ command: Command) async throws -> CommandResult {
        recorded.withLock { $0.append(command.arguments) }
        return CommandResult(exitCode: 0, standardOutput: Data(), standardError: Data())
    }
}
#endif
