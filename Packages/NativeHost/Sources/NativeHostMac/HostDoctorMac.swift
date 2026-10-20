import Darwin
import Foundation
import NativeHost
import NativeHostProtocol

/// The doctor's Mac checks: how the host starts at login, and whether the Mac logs in, stays up and
/// comes back by itself, as a droid has to. Reads only: `pmset -g`, `defaults read`, `fdesetup
/// status`, `launchctl print`.
public struct HostDoctorMac: HostDoctorPlatform {
    /// How this process was started, which says how the host starts at login.
    public struct Launch: Sendable {
        public var arguments: [String]
        public var environment: [String: String]
        /// `Native Host.app` inside Native.app; nil for the standalone `native-host`.
        public var helperBundle: URL?

        public init(arguments: [String], environment: [String: String], helperBundle: URL?) {
            self.arguments = arguments
            self.environment = environment
            self.helperBundle = helperBundle
        }

        public static var current: Launch {
            let bundle = Bundle.main.bundleURL
            return Launch(
                arguments: CommandLine.arguments, environment: ProcessInfo.processInfo.environment,
                helperBundle: bundle.pathExtension == "app" ? bundle : nil)
        }

        /// Native.app, around the helper at `Contents/Library/LoginItems/Native Host.app`.
        public var appBundle: URL? {
            helperBundle?.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
                .deletingLastPathComponent()
        }

        /// The launchd job the app registers the host as (`NativeHostHelper/LaunchAgent.plist`).
        var job: [String: Any]? {
            guard let appBundle else { return nil }
            let plist = appBundle.appending(path: "Contents/Library/LaunchAgents/NativeHost.plist")
            guard let data = try? Data(contentsOf: plist) else { return nil }
            return try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
        }

        var label: String? {
            job?["Label"] as? String
        }

        /// Where this host lives: the channel launchd set, or, run by hand over SSH where nothing set
        /// it, the one the app's job carries (Native Nightly's is `nightly`).
        public var location: HostLocation {
            if environment[HostLocation.channelVariable] != nil {
                return MacHost.location(environment: environment)
            }
            let variables = job?["EnvironmentVariables"] as? [String: String] ?? [:]
            return MacHost.location(environment: variables)
        }
    }

    public var launch: Launch

    public init(launch: Launch = .current) {
        self.launch = launch
    }

    /// For system tools, which need nothing from the login shell.
    static let systemEnvironment = ["PATH": "/usr/bin:/bin:/usr/sbin:/sbin"]

    public func checks(_ context: HostDoctor.Context, machine: any HostDoctorMachine) async -> [HostDoctorCheck] {
        async let loginItem = loginItemCheck(context, machine: machine)
        async let automaticLogin = automaticLoginCheck(machine: machine)
        async let power = powerChecks(context, machine: machine)
        async let remoteLogin = remoteLoginCheck(machine: machine)
        return await [loginItem, automaticLogin] + power + [remoteLogin]
    }

    public func installCommand(for tool: String) -> String? {
        switch tool {
        case "node", "npx": "brew install node"
        case "git": "xcode-select --install"
        case "gh": "brew install gh"
        default: nil
        }
    }

    // MARK: - Login item

    func loginItemCheck(_ context: HostDoctor.Context, machine: any HostDoctorMachine) async -> HostDoctorCheck {
        func check(_ status: HostDoctorCheck.Status, _ detail: String, fix: HostDoctorFix? = nil) -> HostDoctorCheck {
            HostDoctorCheck(
                id: "host.loginItem", group: .host, title: "Starts at login", status: status, detail: detail, fix: fix)
        }
        let openNative = launch.appBundle.map { "open \(Self.quoted($0.path(percentEncoded: false)))" }
        guard context.isHostRunning else {
            return await stoppedHostCheck(machine: machine, openNative: openNative, check: check)
        }
        if launch.arguments.contains(HostLocation.exitWithParentArgument) {
            return check(
                .warning,
                "Native runs its host itself because it isn't allowed in the background, so agents stop when Native quits",
                fix: HostDoctorFix(
                    setting:
                        "System Settings ▸ General ▸ Login Items & Extensions ▸ Allow in the Background ▸ Native, then relaunch Native"
                ))
        }
        if let label = launch.label, launch.environment["XPC_SERVICE_NAME"] == label {
            return launch.location.isDevelopment
                ? check(.info, "A development build's host: it runs for this login session, not at login")
                : check(.ok, "Registered as a login item (\(label)), so it starts at every login")
        }
        return check(
            .warning, "Started by hand, so it won't start again at login or after a crash",
            fix: HostDoctorFix(setting: "Open Native once; it registers its host as a login item", command: openNative))
    }

    /// No host answered (`doctor` over SSH): is anyone logged in to run it, and is it registered?
    private func stoppedHostCheck(
        machine: any HostDoctorMachine, openNative: String?,
        check: (HostDoctorCheck.Status, String, HostDoctorFix?) -> HostDoctorCheck
    ) async -> HostDoctorCheck {
        let console = await machine.run(
            "/usr/bin/stat", ["-f", "%Su", "/dev/console"], environment: Self.systemEnvironment)
        if let user = console?.firstLine, user != machine.userName {
            return check(
                .failed, "Nobody is logged in to this Mac as \(machine.userName), so its host can't run",
                HostDoctorFix(
                    setting: "Log in once (Screen Sharing works), and turn on automatic login (Running unattended)"))
        }
        guard let label = launch.label else {
            return check(
                .failed, "Native's background host isn't running",
                HostDoctorFix(setting: "Open Native once; it registers its host as a login item", command: openNative))
        }
        let job = await machine.run(
            "/bin/launchctl", ["print", "gui/\(getuid())/\(label)"], environment: Self.systemEnvironment)
        if job?.status == 0 {
            return check(
                .warning, "Registered as a login item but stopped (Quit Native and Stop Agents leaves it stopped)",
                HostDoctorFix(
                    setting: "Start it again, or open Native", command: "launchctl kickstart gui/$(id -u)/\(label)"))
        }
        return check(
            .failed, "Not running, and not registered as a login item",
            HostDoctorFix(setting: "Open Native once; it registers its host as a login item", command: openNative))
    }

    /// Quoted for pasting into a shell, since Native.app's path may have spaces in it, and without
    /// the trailing slash a folder's URL path carries.
    static func quoted(_ path: String) -> String {
        "\"\(path.hasSuffix("/") ? String(path.dropLast()) : path)\""
    }
}
