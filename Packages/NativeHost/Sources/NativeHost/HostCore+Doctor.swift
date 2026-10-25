import Foundation
import NativeHostProtocol

// `_native/host/doctor` (docs/droids.md): the doctor's checks with what only the running host knows,
// its agents, the login shell they get, keeping awake, how it updates and the paired-device gateway.
// A host without a platform doctor (Linux, for now) says only what it knows itself, and so does one
// whose policy doesn't allow the checks, which run tools such as `gh` and every agent's CLI.
extension HostCore {
    func doctorReport() async -> HostDoctorReport {
        guard let doctor = configuration.doctor, allowsDoctorChecks else { return doctorReportWithoutChecks() }
        let context = HostDoctor.Context(
            machineName: configuration.machineName, environment: await agentEnvironment(),
            agents: agentOrder.compactMap { agents[$0]?.spec }, keepAwake: keepAwake.state,
            gateway: await doctorGateway?(), isHostRunning: true, updates: updateState)
        // Revoked while the environment was read: nothing runs. Revoked later, each command the
        // checks would run asks again first, and the run is cancelled, ending what it started.
        guard allowsDoctorChecks else { return doctorReportWithoutChecks() }
        var gated = doctor
        gated.machine = PolicyGatedDoctorMachine(machine: doctor.machine) { [weak self] in
            await self?.allowsDoctorChecks ?? false
        }
        let id = UUID()
        let run = Task { await gated.report(context) }
        doctorRuns[id] = run
        defer { doctorRuns[id] = nil }
        let report = await run.value
        return allowsDoctorChecks ? report : doctorReportWithoutChecks()
    }

    var allowsDoctorChecks: Bool {
        allows(.diagnostics) && allows(.loginShell) && allows(.agents)
    }

    /// What the host knows without running anything, and what the policy allows when it's the reason.
    private func doctorReportWithoutChecks() -> HostDoctorReport {
        var checks = [HostDoctor.keepAwakeCheck(keepAwake.state, now: .now), HostDoctor.updatesCheck(updateState)]
        if !allowsDoctorChecks {
            let allowed = policy.capabilities.map(\.action).sorted()
            let detail = [
                policy.reason,
                allowed.isEmpty
                    ? "Nothing that starts processes, listens or updates is allowed"
                    : "Allowed here: \(allowed.joined(separator: ", "))",
            ]
            checks.insert(
                HostDoctorCheck(
                    id: "host.policy", group: .host, title: "Organization policy",
                    status: policy.mode == .blocked ? .failed : .warning,
                    detail: detail.compactMap(\.self).joined(separator: " ")),
                at: 0)
        }
        return HostDoctorReport(
            machineName: configuration.machineName, checkedAt: .now, isHostRunning: true, checks: checks)
    }
}

/// The doctor's machine, asking the host's policy before each command or connection it makes.
private struct PolicyGatedDoctorMachine: HostDoctorMachine {
    let machine: any HostDoctorMachine
    let isAllowed: @Sendable () async -> Bool

    var userName: String { machine.userName }
    var homeDirectory: String { machine.homeDirectory }

    func isExecutableFile(atPath path: String) -> Bool {
        machine.isExecutableFile(atPath: path)
    }

    func run(_ executable: String, _ arguments: [String], environment: [String: String]) async -> HostDoctorOutput? {
        guard await isAllowed() else { return nil }
        return await machine.run(executable, arguments, environment: environment)
    }

    func availableSpace(at path: String) -> Int64? {
        machine.availableSpace(at: path)
    }

    func networkAddresses() -> [String] {
        machine.networkAddresses()
    }

    func acceptsConnections(onPort port: UInt16) async -> Bool {
        guard await isAllowed() else { return false }
        return await machine.acceptsConnections(onPort: port)
    }
}
