import Foundation
import NativeHostProtocol
import ServiceManagement

/// Native's launchd registration for its background host (`docs/durability.md`). The plist ships in
/// the app bundle, generated at build time; it also carries the host's channel, so this app and the
/// host it registers always agree on where the host lives.
struct HostRegistration {
    static let plistName = "NativeHost.plist"

    private let service = SMAppService.agent(plistName: Self.plistName)

    /// Where this build's host keeps its socket and store.
    var location: HostLocation {
        HostLocation.standard(channel: Self.channel)
    }

    var status: SMAppService.Status {
        service.status
    }

    /// Registers the host with launchd, which starts it now and at every login. Registering again
    /// is harmless.
    func register() throws {
        try service.register()
    }

    /// Unregisters the host. launchd stops it, and its agents with it.
    func unregister() async throws {
        try await service.unregister()
    }

    /// The channel the build baked into the plist: empty for release builds, one per build folder for
    /// development builds.
    private static var channel: String {
        let url = Bundle.main.bundleURL.appending(path: "Contents/Library/LaunchAgents/\(plistName)")
        guard let data = try? Data(contentsOf: url),
              let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
              let environment = plist["EnvironmentVariables"] as? [String: String] else { return "" }
        return environment[HostLocation.channelVariable] ?? ""
    }
}
