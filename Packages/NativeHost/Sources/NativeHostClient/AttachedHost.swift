#if os(macOS)
import Foundation
import NativeHostProtocol

/// A host the app runs as its own child, for when the user turned Native's background activity off
/// (System Settings › Login Items › Allow in the Background): the embedded helper with
/// `--exit-with-parent`, so it stops its agents and exits when the app goes, even if the app is
/// killed. launchd doesn't restart it; the app starts it again if it stops (`onExit`).
public final class AttachedHost: @unchecked Sendable {
    // `Process` isn't Sendable, but the calls made on it here (`isRunning`, `terminate`,
    // `processIdentifier`) are safe from any thread.
    private let process: Process

    private init(process: Process) {
        self.process = process
    }

    /// The helper's executable inside the app bundle.
    public static func helper(in appBundle: URL) -> URL {
        appBundle.appending(path: "Contents/Library/LoginItems/Native Host.app/Contents/MacOS/Native Host")
    }

    /// Starts the app's own helper for `location`.
    public static func start(
        appBundle: URL, location: HostLocation, onExit: @escaping @Sendable (Int32) -> Void = { _ in }
    ) throws -> AttachedHost {
        try start(executable: helper(in: appBundle), location: location, onExit: onExit)
    }

    /// Starts `executable` (the helper, or `native-host serve`) as an attached host. It gets the
    /// environment launchd would give it, plus the location's channel, and nothing else of the app's.
    public static func start(
        executable: URL, arguments: [String] = [], location: HostLocation,
        onExit: @escaping @Sendable (Int32) -> Void = { _ in }
    ) throws -> AttachedHost {
        let process = Process()
        process.executableURL = executable
        process.arguments = arguments + [HostLocation.exitWithParentArgument]
        process.environment = environment(for: location)
        process.standardInput = FileHandle.nullDevice
        process.terminationHandler = { onExit($0.terminationStatus) }
        try process.run()
        return AttachedHost(process: process)
    }

    public var isRunning: Bool {
        process.isRunning
    }

    public var processIdentifier: Int32 {
        process.processIdentifier
    }

    /// Ends the host at once. Prefer `NativeHostClient.shutdownHost(stopAgents: true)`, which ends
    /// running turns as stopped first.
    public func terminate() {
        if process.isRunning {
            process.terminate()
        }
    }

    /// What launchd gives a user agent, so the attached host behaves like the registered one: it
    /// reads the user's login-shell environment for agents itself.
    static func environment(
        for location: HostLocation, from current: [String: String] = ProcessInfo.processInfo.environment
    ) -> [String: String] {
        var environment = current.filter { ["HOME", "USER", "LOGNAME", "SHELL", "TMPDIR"].contains($0.key) }
        environment["PATH"] = "/usr/bin:/bin:/usr/sbin:/sbin"
        environment[HostLocation.channelVariable] = location.channel
        if location.isDevelopment {
            environment[HostLocation.developmentVariable] = "1"
        }
        return environment
    }
}
#endif
