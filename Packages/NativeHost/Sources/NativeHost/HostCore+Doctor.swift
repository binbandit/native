import Foundation
import NativeHostProtocol

// `_native/host/doctor` (docs/droids.md): the doctor's checks with what only the running host knows,
// its agents, the login shell they get, keeping awake, how it updates and the paired-device gateway.
// A host without a platform doctor (Linux, for now) says only what it knows itself.
extension HostCore {
    func doctorReport() async -> HostDoctorReport {
        guard let doctor = configuration.doctor else {
            return HostDoctorReport(
                machineName: configuration.machineName, checkedAt: .now, isHostRunning: true,
                checks: [
                    HostDoctor.keepAwakeCheck(keepAwake.state, now: .now), HostDoctor.updatesCheck(updateState),
                ])
        }
        let context = HostDoctor.Context(
            machineName: configuration.machineName, environment: await agentEnvironment(),
            agents: agentOrder.compactMap { agents[$0]?.spec }, keepAwake: keepAwake.state,
            gateway: await doctorGateway?(), isHostRunning: true, updates: updateState)
        return await doctor.report(context)
    }
}
