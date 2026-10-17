#if os(macOS)
import Exec
import Foundation
import NativeHostProtocol

/// Runs a development build's host as a launchd job for this login session only: launchd starts it,
/// restarts it if it crashes and stops it at logout, but it never becomes a login item. Release
/// builds register with `SMAppService` instead, so the host starts at every login.
///
/// Development builds come and go from many build folders; a login item per build would pile up in
/// System Settings and pop "Background Items Added" for each one (`docs/durability.md`).
public struct LaunchdSessionJob: Sendable {
    /// The launchd plist the build generated, with `BundleProgram` relative to the app bundle.
    public let bundledPlist: URL
    public let appBundle: URL
    public let location: HostLocation
    private let runner: any CommandRunner

    public init(
        bundledPlist: URL, appBundle: URL, location: HostLocation, runner: any CommandRunner = LocalCommandRunner()
    ) {
        self.bundledPlist = bundledPlist
        self.appBundle = appBundle
        self.location = location
        self.runner = runner
    }

    public enum Failure: Error, LocalizedError {
        case unreadablePlist
        case launchctl(String)

        public var errorDescription: String? {
            switch self {
            case .unreadablePlist: "The app's launchd plist for the host is missing or unreadable."
            case .launchctl(let message): "launchctl failed: \(message)"
            }
        }
    }

    /// Loads the job (if it isn't) and makes sure the host is running.
    public func start() async throws {
        let (label, plist) = try sessionPlist()
        try location.prepare()
        let path = location.directory.appending(path: "launchd.plist")
        try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0).write(
            to: path, options: .atomic)
        // The cleanup script disables stale labels; this build wants its own back. Bootstrapping a
        // job that's already loaded fails harmlessly; kickstart then starts it if it exited (a
        // stopped or idle host).
        _ = try await launchctl(["enable", "\(domain)/\(label)"])
        _ = try await launchctl(["bootstrap", domain, path.path(percentEncoded: false)])
        let kick = try await launchctl(["kickstart", "\(domain)/\(label)"])
        guard kick.succeeded else { throw Failure.launchctl(kick.errorOutput) }
    }

    /// Stops the host and unloads the job.
    public func stop() async throws {
        let (label, _) = try sessionPlist()
        _ = try await launchctl(["bootout", "\(domain)/\(label)"])
    }

    /// The bundled plist, pointed at the helper by absolute path (launchd only resolves
    /// `BundleProgram` for jobs registered through `SMAppService`).
    private func sessionPlist() throws -> (String, [String: Any]) {
        guard let data = try? Data(contentsOf: bundledPlist),
            var plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
            let label = plist["Label"] as? String, let program = plist["BundleProgram"] as? String
        else {
            throw Failure.unreadablePlist
        }
        plist["BundleProgram"] = nil
        plist["AssociatedBundleIdentifiers"] = nil
        plist["Program"] = appBundle.appending(path: program).path(percentEncoded: false)
        return (label, plist)
    }

    private var domain: String {
        "gui/\(getuid())"
    }

    private func launchctl(_ arguments: [String]) async throws -> CommandResult {
        try await runner.run(
            Command(
                "/bin/launchctl", arguments, environment: ProcessInfo.processInfo.environment, timeout: .seconds(10)))
    }
}
#endif
