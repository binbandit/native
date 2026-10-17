import Foundation
import NativeHostClient
import NativeHostProtocol
import ServiceManagement

/// How the app starts its background host (`docs/durability.md`). The launchd plist ships in the app
/// bundle, generated at build time; it carries the host's channel, so this app and the host it
/// starts always agree on where the host lives.
///
/// Release builds register a login item with `SMAppService`: the host starts at every login.
/// Development builds (a channel per build folder) run a launchd job for this login session only,
/// so the many builds agents make never pile up as login items.
struct HostRegistration {
    static let plistName = "NativeHost.plist"

    enum Status: Equatable {
        case registered
        /// The user turned Native off under Login Items › Allow in the Background.
        case needsApproval
        case notRegistered
    }

    private let service = SMAppService.agent(plistName: Self.plistName)

    /// Where this build's host keeps its socket and store.
    var location: HostLocation {
        HostLocation.standard(channel: Self.channel)
    }

    var isDevelopmentBuild: Bool {
        !Self.channel.isEmpty
    }

    var status: Status {
        if isDevelopmentBuild { return .registered }
        return switch service.status {
        case .enabled: .registered
        case .requiresApproval: .needsApproval
        default: .notRegistered
        }
    }

    /// Starts the host now (and, for release builds, at every login). Doing it again is harmless.
    func register() async throws {
        if isDevelopmentBuild {
            // Earlier development builds registered login items; take this build's back out.
            if service.status != .notRegistered {
                try? await service.unregister()
            }
            try await sessionJob.start()
        } else {
            try service.register()
        }
    }

    /// Stops the host and its agents, and keeps it from starting again.
    func unregister() async throws {
        if isDevelopmentBuild {
            try await sessionJob.stop()
        } else {
            try await service.unregister()
        }
    }

    private var sessionJob: LaunchdSessionJob {
        LaunchdSessionJob(bundledPlist: Self.bundledPlist, appBundle: Bundle.main.bundleURL, location: location)
    }

    private static var bundledPlist: URL {
        Bundle.main.bundleURL.appending(path: "Contents/Library/LaunchAgents/\(plistName)")
    }

    /// The channel the build baked into the plist: empty for release builds, one per build folder for
    /// development builds.
    private static var channel: String {
        guard let data = try? Data(contentsOf: bundledPlist),
              let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
              let environment = plist["EnvironmentVariables"] as? [String: String] else { return "" }
        return environment[HostLocation.channelVariable] ?? ""
    }
}
