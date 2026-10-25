#if os(Linux)
import Foundation
import NativeHost
import NativeHostProtocol
import UserShell

/// The host as it runs on Linux: started by hand, over SSH or by a systemd user unit, with the user's
/// login-shell environment. What's still Mac-only (peer code-signature checks, attached hosts,
/// updating itself, plugin assets, Native's tools for agents) is in docs/durability.md, "Any machine
/// can be a host".
enum LinuxHost {
    static func configuration(
        location: HostLocation, info: PeerInfo, inheritEnvironment: Bool, pluginsDirectory: URL?
    ) -> HostCore.Configuration {
        HostCore.Configuration(
            location: location,
            hostInfo: info,
            machineName: ProcessInfo.processInfo.hostName,
            bootTime: bootTime(),
            // A systemd unit's environment is as bare as launchd's.
            environment: { @Sendable in
                inheritEnvironment ? ProcessInfo.processInfo.environment : await LoginShell.environment()
            },
            idleExit: location.isDevelopment ? .seconds(15 * 60) : nil,
            pluginsDirectory: pluginsDirectory,
            updates: .none(
                current: HostUpdateStatus.Build(
                    version: info.version, build: info.build,
                    channel: location.channel.isEmpty ? "stable" : location.channel),
                reason: "Updates aren't available on this host yet."),
            exit: { status in exit(status) },
            // No managed source here yet: a deployment file asks for one, and blocks the host.
            policy: LinuxHostPolicySource()
        )
    }

    /// When the machine booted, from the kernel's `btime` in /proc/stat, to tell a restart from the
    /// host stopping.
    static func bootTime() -> Date? {
        guard let stat = try? String(contentsOfFile: "/proc/stat", encoding: .utf8) else { return nil }
        let line = stat.split(separator: "\n").first { $0.hasPrefix("btime ") }
        return line.flatMap { Double($0.dropFirst("btime ".count)) }.map(Date.init(timeIntervalSince1970:))
    }
}
#endif
