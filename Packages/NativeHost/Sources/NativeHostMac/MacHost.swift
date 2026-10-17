import Darwin
import Foundation
import NativeHost
import NativeHostProtocol
import UserShell

/// The host as it runs on a Mac: launched by launchd from the app bundle (or by hand from
/// `native-host`), with the user's login-shell environment and code-signature checks on clients.
public enum MacHost {
    /// Where this process's host lives: the channel its launchd plist set, or the standard location.
    public static func location(environment: [String: String] = ProcessInfo.processInfo.environment) -> HostLocation {
        HostLocation.standard(channel: environment[HostLocation.channelVariable] ?? "")
    }

    public static func configuration(location: HostLocation, info: PeerInfo, inheritEnvironment: Bool = false) -> HostCore.Configuration {
        HostCore.Configuration(
            location: location,
            hostInfo: info,
            machineName: Host.current().localizedName ?? ProcessInfo.processInfo.hostName,
            bootTime: bootTime(),
            // Tests and `native-host --inherit-environment` pass their own; launchd's is bare.
            environment: { @Sendable in inheritEnvironment ? ProcessInfo.processInfo.environment : await LoginShell.environment() },
            // A channel means a development build; its host shouldn't outlive interest in it.
            idleExit: location.channel.isEmpty ? nil : .seconds(15 * 60),
            exit: { status in Darwin.exit(status) }
        )
    }

    /// When the Mac booted, to tell a restart from the host stopping.
    public static func bootTime() -> Date? {
        var time = timeval()
        var size = MemoryLayout<timeval>.size
        var name: [Int32] = [CTL_KERN, KERN_BOOTTIME]
        guard sysctl(&name, 2, &time, &size, nil, 0) == 0 else { return nil }
        return Date(timeIntervalSince1970: Double(time.tv_sec) + Double(time.tv_usec) / 1_000_000)
    }
}
