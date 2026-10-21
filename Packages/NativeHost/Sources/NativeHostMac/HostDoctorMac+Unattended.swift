import Foundation
import NativeHost
import NativeHostProtocol

// What a Mac that runs without anyone at it needs: to log in by itself after a restart, to stay
// awake, to wake for the network and to start again after a power failure; and SSH, to set it up.
extension HostDoctorMac {
    func automaticLoginCheck(machine: any HostDoctorMachine) async -> HostDoctorCheck {
        func check(_ status: HostDoctorCheck.Status, _ detail: String, fix: HostDoctorFix? = nil) -> HostDoctorCheck {
            HostDoctorCheck(
                id: "unattended.autoLogin", group: .unattended, title: "Logs in by itself", status: status,
                detail: detail, fix: fix)
        }
        async let autoLogin = machine.run(
            "/usr/bin/defaults", ["read", "/Library/Preferences/com.apple.loginwindow", "autoLoginUser"],
            environment: Self.systemEnvironment)
        async let fileVault = machine.run("/usr/bin/fdesetup", ["status"], environment: Self.systemEnvironment)
        let user = await autoLogin.flatMap { $0.status == 0 ? $0.firstLine : nil }
        let me = machine.userName
        let setting = "System Settings ▸ Users & Groups ▸ Automatically log in as ▸ \(me)"
        if user == me {
            return check(.ok, "Logs in as \(me) after a restart, so the host starts with nobody at the Mac")
        }
        if await fileVault?.output.contains("FileVault is On") == true {
            return check(
                .warning,
                "FileVault is on, so after a restart the Mac waits for a password before anything runs, the host included",
                fix: HostDoctorFix(
                    setting:
                        "Either turn FileVault off and log in automatically (docs/droids.md, \"Staying logged in\"), or unlock it after each restart. For a planned restart, this unlocks it once:",
                    command: "sudo fdesetup authrestart"))
        }
        if let user {
            return check(
                .warning, "Logs in automatically as \(user), not \(me), so this account's host doesn't start",
                fix: HostDoctorFix(setting: setting))
        }
        return check(
            .warning, "Doesn't log in by itself: after a restart nothing runs until someone logs in",
            fix: HostDoctorFix(setting: setting))
    }

    // MARK: - Power

    func powerChecks(_ context: HostDoctor.Context, machine: any HostDoctorMachine) async -> [HostDoctorCheck] {
        guard let result = await machine.run("/usr/bin/pmset", ["-g"], environment: Self.systemEnvironment),
            result.status == 0
        else {
            return [
                HostDoctorCheck(
                    id: "unattended.sleep", group: .unattended, title: "Stays awake", status: .unknown,
                    detail: "Couldn't read the power settings (`pmset -g`)")
            ]
        }
        let settings = Self.powerSettings(result.output)
        let neverSleeps = settings["SleepDisabled"] == 1 || settings["sleep"] == 0
        return [
            sleepCheck(settings, neverSleeps: neverSleeps, keepAwake: context.keepAwake),
            wakeCheck(settings, neverSleeps: neverSleeps), powerFailureCheck(settings),
        ]
    }

    /// `pmset -g`'s numeric settings by name ("sleep 1 (sleep prevented by …)" reads as 1).
    static func powerSettings(_ output: String) -> [String: Int] {
        var settings: [String: Int] = [:]
        for line in output.split(whereSeparator: \.isNewline) {
            let words = line.split(whereSeparator: \.isWhitespace)
            guard words.count >= 2, let value = Int(words[1]) else { continue }
            settings[String(words[0])] = value
        }
        return settings
    }

    func sleepCheck(_ settings: [String: Int], neverSleeps: Bool, keepAwake: HostKeepAwakeState?) -> HostDoctorCheck {
        func check(_ status: HostDoctorCheck.Status, _ detail: String, fix: HostDoctorFix? = nil) -> HostDoctorCheck {
            HostDoctorCheck(
                id: "unattended.sleep", group: .unattended, title: "Stays awake", status: status, detail: detail,
                fix: fix)
        }
        if neverSleeps {
            return check(.ok, "Never sleeps on its own")
        }
        guard let minutes = settings["sleep"] else {
            return check(.unknown, "`pmset -g` didn't say when it sleeps")
        }
        let keepsAwakeForAgents = keepAwake.map { $0.isSupported && $0.policy.mode != .off } ?? false
        let idle = minutes == 1 ? "1 minute" : "\(minutes) minutes"
        return check(
            .warning,
            keepsAwakeForAgents
                ? "Sleeps after \(idle) idle. Native keeps it awake while agents work, but asleep it can't take new work"
                : "Sleeps after \(idle) idle, even while agents work",
            fix: HostDoctorFix(
                setting: "System Settings ▸ Energy ▸ Prevent automatic sleeping when the display is off",
                command: "sudo pmset -a sleep 0"))
    }

    func wakeCheck(_ settings: [String: Int], neverSleeps: Bool) -> HostDoctorCheck {
        func check(_ status: HostDoctorCheck.Status, _ detail: String, fix: HostDoctorFix? = nil) -> HostDoctorCheck {
            HostDoctorCheck(
                id: "unattended.wakeForNetwork", group: .unattended, title: "Wakes for network access", status: status,
                detail: detail, fix: fix)
        }
        switch settings["womp"] {
        case 1?: return check(.ok, "On")
        case nil: return check(.info, "Not offered on this Mac")
        case _ where neverSleeps: return check(.info, "Off, which doesn't matter while it never sleeps")
        default:
            return check(
                .warning, "Off: asleep, it can't be reached until someone wakes it",
                fix: HostDoctorFix(
                    setting: "System Settings ▸ Energy ▸ Wake for network access", command: "sudo pmset -a womp 1"))
        }
    }

    func powerFailureCheck(_ settings: [String: Int]) -> HostDoctorCheck {
        func check(_ status: HostDoctorCheck.Status, _ detail: String, fix: HostDoctorFix? = nil) -> HostDoctorCheck {
            HostDoctorCheck(
                id: "unattended.powerFailure", group: .unattended, title: "Starts after a power failure",
                status: status, detail: detail, fix: fix)
        }
        switch settings["autorestart"] {
        case 1?: return check(.ok, "On")
        case nil: return check(.info, "Not offered on this Mac")
        default:
            return check(
                .warning, "Off: after a power cut it stays off until someone presses its power button",
                fix: HostDoctorFix(
                    setting: "System Settings ▸ Energy ▸ Start up automatically after a power failure",
                    command: "sudo pmset -a autorestart 1"))
        }
    }

    // MARK: - SSH

    func remoteLoginCheck(machine: any HostDoctorMachine) async -> HostDoctorCheck {
        let isOn = await machine.acceptsConnections(onPort: 22)
        return HostDoctorCheck(
            id: "system.remoteLogin", group: .system, title: "Remote Login (SSH)", status: isOn ? .ok : .warning,
            detail: isOn
                ? "On: you can sign agents in and run `doctor` over SSH"
                : "Off: you can't sign agents in or check this Mac over SSH",
            fix: isOn
                ? nil
                : HostDoctorFix(
                    setting: "System Settings ▸ General ▸ Sharing ▸ Remote Login",
                    command: "sudo systemsetup -setremotelogin on"))
    }
}
