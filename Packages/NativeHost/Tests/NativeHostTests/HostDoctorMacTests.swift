#if os(macOS)
import Foundation
import NativeHostMac
import NativeHostProtocol
import Testing

@testable import NativeHost

/// The doctor's Mac checks against a fake Mac: `pmset -g`, the login window's settings, FileVault,
/// and how the host was started.
@Suite("Host doctor on a Mac")
struct HostDoctorMacTests {
    static let label = "dev.binbandit.native.host"

    /// A Native.app whose launchd plist names `label`, around its helper.
    final class AppBundle {
        let root = FileManager.default.temporaryDirectory.appending(path: "doctor-\(UUID().uuidString.prefix(8))")
        var app: URL { root.appending(path: "Native.app") }
        var helper: URL { app.appending(path: "Contents/Library/LoginItems/Native Host.app") }

        init(channel: String = "") throws {
            let agents = app.appending(path: "Contents/Library/LaunchAgents")
            try FileManager.default.createDirectory(at: agents, withIntermediateDirectories: true)
            try FileManager.default.createDirectory(at: helper, withIntermediateDirectories: true)
            let plist: [String: Any] = [
                "Label": HostDoctorMacTests.label,
                "EnvironmentVariables": ["NATIVE_HOST_CHANNEL": channel, "NATIVE_HOST_DEVELOPMENT": ""],
            ]
            let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
            try data.write(to: agents.appending(path: "NativeHost.plist"))
        }

        deinit {
            try? FileManager.default.removeItem(at: root)
        }

        func launch(arguments: [String] = ["Native Host"], environment: [String: String] = [:]) -> HostDoctorMac.Launch
        {
            HostDoctorMac.Launch(arguments: arguments, environment: environment, helperBundle: helper)
        }
    }

    private func checks(
        _ machine: FakeDoctorMachine, launch: HostDoctorMac.Launch, isHostRunning: Bool = true,
        keepAwake: HostKeepAwakeState? = nil
    ) async -> [String: HostDoctorCheck] {
        let context = HostDoctor.Context(
            machineName: "mini", environment: [:], agents: [], keepAwake: keepAwake, isHostRunning: isHostRunning)
        let checks = await HostDoctorMac(launch: launch).checks(context, machine: machine)
        return Dictionary(uniqueKeysWithValues: checks.map { ($0.id, $0) })
    }

    private func pmset(_ lines: String) -> HostDoctorOutput {
        HostDoctorOutput(status: 0, output: "System-wide power settings:\nCurrently in use:\n\(lines)")
    }

    @Test("Power: a Mac that never sleeps is fine; one that sleeps, can't wake and stays off after a power cut warns")
    func power() async throws {
        let bundle = try AppBundle()
        var machine = FakeDoctorMachine()
        machine.outputs["/usr/bin/pmset -g"] = pmset(
            " sleep                0\n womp                 1\n autorestart          1\n")
        let ready = await checks(machine, launch: bundle.launch())
        #expect(ready["unattended.sleep"]?.status == .ok)
        #expect(ready["unattended.wakeForNetwork"]?.status == .ok)
        #expect(ready["unattended.powerFailure"]?.status == .ok)

        machine.outputs["/usr/bin/pmset -g"] = pmset(
            " Sleep On Power Button 1\n sleep                10 (sleep prevented by caffeinate)\n womp                 0\n autorestart          0\n"
        )
        let laptop = await checks(machine, launch: bundle.launch())
        let sleep = try #require(laptop["unattended.sleep"])
        #expect(sleep.status == .warning)
        #expect(sleep.detail == "Sleeps after 10 minutes idle, even while agents work")
        #expect(sleep.fix?.command == "sudo pmset -a sleep 0")
        #expect(laptop["unattended.wakeForNetwork"]?.fix?.command == "sudo pmset -a womp 1")
        #expect(laptop["unattended.powerFailure"]?.fix?.command == "sudo pmset -a autorestart 1")

        machine.outputs["/usr/bin/pmset -g"] = pmset(" sleep                1\n")
        let oneMinute = await checks(machine, launch: bundle.launch())
        #expect(oneMinute["unattended.sleep"]?.detail == "Sleeps after 1 minute idle, even while agents work")

        // `pmset disablesleep 1` keeps it up whatever `sleep` says, so waking for the network is moot.
        machine.outputs["/usr/bin/pmset -g"] = HostDoctorOutput(
            status: 0,
            output: "System-wide power settings:\n SleepDisabled\t\t1\nCurrently in use:\n sleep 10\n womp 0\n")
        let disabled = await checks(machine, launch: bundle.launch())
        #expect(disabled["unattended.sleep"]?.status == .ok)
        #expect(disabled["unattended.wakeForNetwork"]?.status == .info)
        #expect(disabled["unattended.powerFailure"]?.status == .info)
    }

    @Test("Automatic login: as this user, blocked by FileVault, as someone else, or off")
    func automaticLogin() async throws {
        let bundle = try AppBundle()
        let autoLogin = "/usr/bin/defaults read /Library/Preferences/com.apple.loginwindow autoLoginUser"
        var machine = FakeDoctorMachine()
        machine.outputs[autoLogin] = HostDoctorOutput(status: 0, output: "brayden\n")
        #expect(await checks(machine, launch: bundle.launch())["unattended.autoLogin"]?.status == .ok)

        machine.outputs[autoLogin] = HostDoctorOutput(status: 1, output: "The domain/default pair does not exist")
        machine.outputs["/usr/bin/fdesetup status"] = HostDoctorOutput(status: 0, output: "FileVault is On.\n")
        let fileVault = try #require(await checks(machine, launch: bundle.launch())["unattended.autoLogin"])
        #expect(fileVault.status == .warning)
        #expect(fileVault.fix?.command == "sudo fdesetup authrestart")

        machine.outputs["/usr/bin/fdesetup status"] = HostDoctorOutput(status: 0, output: "FileVault is Off.\n")
        machine.outputs[autoLogin] = HostDoctorOutput(status: 0, output: "guest\n")
        let other = try #require(await checks(machine, launch: bundle.launch())["unattended.autoLogin"])
        #expect(other.detail == "Logs in automatically as guest, not brayden, so this account's host doesn't start")

        machine.outputs[autoLogin] = nil
        let off = try #require(await checks(machine, launch: bundle.launch())["unattended.autoLogin"])
        #expect(off.fix?.setting == "System Settings ▸ Users & Groups ▸ Automatically log in as ▸ brayden")
    }

    @Test("Starting at login: launchd's job, a host the app started itself, and one started by hand")
    func loginItem() async throws {
        let bundle = try AppBundle()
        let machine = FakeDoctorMachine()
        let registered = await checks(machine, launch: bundle.launch(environment: ["XPC_SERVICE_NAME": Self.label]))
        #expect(registered["host.loginItem"]?.status == .ok)

        let attached = await checks(machine, launch: bundle.launch(arguments: ["Native Host", "--exit-with-parent"]))
        #expect(attached["host.loginItem"]?.status == .warning)
        #expect(attached["host.loginItem"]?.fix?.setting?.contains("Allow in the Background") == true)

        let byHand = try #require(await checks(machine, launch: bundle.launch())["host.loginItem"])
        #expect(byHand.status == .warning)
        #expect(byHand.fix?.command == "open \"\(bundle.app.path(percentEncoded: false))\"")
    }

    @Test("With no host answering: nobody logged in, stopped on purpose, or never registered")
    func stoppedHost() async throws {
        let bundle = try AppBundle()
        let console = "/usr/bin/stat -f %Su /dev/console"
        let job = "/bin/launchctl print gui/\(getuid())/\(Self.label)"
        var machine = FakeDoctorMachine()
        machine.outputs[console] = HostDoctorOutput(status: 0, output: "root\n")
        let loggedOut = try #require(
            await checks(machine, launch: bundle.launch(), isHostRunning: false)["host.loginItem"])
        #expect(loggedOut.status == .failed)
        #expect(loggedOut.detail.hasPrefix("Nobody is logged in"))

        machine.outputs[console] = HostDoctorOutput(status: 0, output: "brayden\n")
        machine.outputs[job] = HostDoctorOutput(status: 0, output: "state = not running\n")
        let stopped = try #require(
            await checks(machine, launch: bundle.launch(), isHostRunning: false)["host.loginItem"])
        #expect(stopped.status == .warning)
        #expect(stopped.fix?.command == "launchctl kickstart gui/$(id -u)/\(Self.label)")

        machine.outputs[job] = HostDoctorOutput(status: 113, output: "Could not find service")
        let missing = try #require(
            await checks(machine, launch: bundle.launch(), isHostRunning: false)["host.loginItem"])
        #expect(missing.status == .failed)
    }

    @Test("Remote Login is on when something answers on port 22")
    func remoteLogin() async {
        let bundle = try? AppBundle()
        var machine = FakeDoctorMachine()
        let launch = HostDoctorMac.Launch(arguments: [], environment: [:], helperBundle: bundle?.helper)
        #expect(await checks(machine, launch: launch)["system.remoteLogin"]?.status == .ok)
        machine.listening = []
        let off = await checks(machine, launch: launch)["system.remoteLogin"]
        #expect(off?.status == .warning)
        #expect(off?.fix?.command == "sudo systemsetup -setremotelogin on")
    }

    @Test("Run over SSH, the doctor finds Native Nightly's host by the channel its app's job carries")
    func location() throws {
        let bundle = try AppBundle(channel: "nightly")
        #expect(bundle.launch().location.channel == "nightly")
        #expect(bundle.launch(environment: ["NATIVE_HOST_CHANNEL": "abc"]).location.channel == "abc")
    }
}
#endif
