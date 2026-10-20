import Darwin
import Foundation
import NativeHost
import NativeHostProtocol
import UserShell

// `doctor`, for SSH (docs/droids.md): `"/Applications/Native.app/Contents/Library/LoginItems/Native
// Host.app/Contents/MacOS/Native Host" doctor`, or `native-host doctor`. It prints the running host's
// report, or checks the Mac without the host when none answers.
extension HostDoctorMac {
    /// Prints the report for the host at `location` and exits: 1 when a check failed, so scripts can
    /// tell. The helper passes `Launch.current.location`, which finds Native Nightly's channel too.
    public static func runCommand(location: HostLocation, launch: Launch = .current, version: PeerInfo) -> Never {
        Task {
            let report = await report(at: location, launch: launch, version: version)
            print(report.text)
            exit(report.status == .failed ? 1 : 0)
        }
        dispatchMain()
    }

    static func report(at location: HostLocation, launch: Launch, version: PeerInfo) async -> HostDoctorReport {
        switch await askHost(at: location, version: version) {
        case .answered(let report):
            return report
        case .tooOld(let host):
            return HostDoctorReport(
                machineName: MacHost.machineName, checkedAt: .now, isHostRunning: true,
                checks: [
                    HostDoctorCheck(
                        id: "host.version", group: .host, title: "Background host", status: .failed,
                        detail: "The running host (\(host.version)) is older than this doctor and can't answer",
                        fix: HostDoctorFix(setting: "Update Native on this Mac, or restart the host from Native"))
                ])
        case .notRunning:
            let doctor = HostDoctor(machine: HostDoctorMacMachine(), platform: HostDoctorMac(launch: launch))
            let context = HostDoctor.Context(
                machineName: MacHost.machineName, environment: await LoginShell.environment(), agents: [],
                keepAwake: nil, isHostRunning: false)
            return await doctor.report(context)
        }
    }

    private enum HostAnswer {
        case answered(HostDoctorReport)
        case tooOld(PeerInfo)
        case notRunning
    }

    private static func askHost(at location: HostLocation, version: PeerInfo) async -> HostAnswer {
        guard let socket = try? UnixSocket.connect(to: location.socketPath) else { return .notRunning }
        let peer = JSONRPCPeer(channel: ByteChannel.socket(socket, label: "doctor"), label: "doctor") { _ in }
        peer.start()
        defer { peer.close() }
        guard
            let handshake = try? await peer.request(
                HostProtocol.Method.initialize, InitializeParams(clientInfo: version), as: FrozenHandshake.self)
        else { return .notRunning }
        do {
            return .answered(
                try await peer.request(HostProtocol.Method.doctor, EmptyMessage(), as: HostDoctorReport.self))
        } catch {
            return .tooOld(handshake.hostInfo)
        }
    }
}
