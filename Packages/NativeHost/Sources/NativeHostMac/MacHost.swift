import Darwin
import Foundation
import NativeHost
import NativeHostProtocol
import NativePolicy
import SessionTitling
import UserShell

/// The host as it runs on a Mac: launched by launchd from the app bundle (or by hand from
/// `native-host`), with the user's login-shell environment and code-signature checks on clients.
public enum MacHost {
    /// Where this process's host lives: the channel its launchd plist set, or the standard location.
    public static func location(environment: [String: String] = ProcessInfo.processInfo.environment) -> HostLocation {
        HostLocation.standard(
            channel: environment[HostLocation.channelVariable] ?? "",
            isDevelopment: environment[HostLocation.developmentVariable] == "1"
        )
    }

    /// The organization's policy comes from the managed preferences of this host's domain
    /// (`MacHostPolicySource.domain`); a host with no domain is unmanaged.
    public static func configuration(
        location: HostLocation, info: PeerInfo, inheritEnvironment: Bool = false, pluginsDirectory: URL? = nil
    ) -> HostCore.Configuration {
        let policy = policySource(location: location)
        var configuration = HostCore.Configuration(
            location: location,
            hostInfo: info,
            machineName: Host.current().localizedName ?? ProcessInfo.processInfo.hostName,
            bootTime: bootTime(),
            // Tests and `native-host --inherit-environment` pass their own; launchd's is bare.
            environment: { @Sendable in
                inheritEnvironment ? ProcessInfo.processInfo.environment : await LoginShell.environment()
            },
            // A development build's host shouldn't outlive interest in it.
            idleExit: location.isDevelopment ? .seconds(15 * 60) : nil,
            pluginsDirectory: pluginsDirectory,
            updates: MacHostUpdates.environment(location: location, mirror: { policy?.updateFeedURL() }),
            exit: { status in Darwin.exit(status) },
            fileWatching: FSEventsFileWatching(),
            nativeSkills: bundledSkills(),
            // Writes nothing where Apple Intelligence is off; clients then write titles instead.
            titleGenerator: OnDeviceTitleGenerator(),
            keepAwake: MacPowerBackend(), systemInfo: systemInfo(),
            doctor: HostDoctor(machine: HostDoctorMacMachine(), platform: HostDoctorMac()),
            credentials: credentialStore(for: location),
            policy: policy ?? FixedHostPolicySource(.unrestricted)
        )
        configuration.actionExecutable = Bundle.main.executableURL
        return configuration
    }

    /// The managed preferences this process's host follows, or nil when no organization can manage it.
    /// A restricted enrollment is kept beside the host's store, apart from any preference.
    public static func policySource(location: HostLocation, bundle: Bundle = .main) -> MacHostPolicySource? {
        let channel = MacHostUpdates.channel(location: location, bundle: bundle)
        let enrollment = FilePolicyEnrollmentStore(url: location.directory.appending(path: "policy-enrollment.json"))
        return MacHostPolicySource.domain(bundle: bundle, channel: channel).map {
            MacHostPolicySource(domain: $0, channel: channel, enrollment: enrollment)
        }
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
