import Foundation
import NativeHostClient
import NativeHostProtocol
import Observation

/// One run of the host doctor for a host (docs/droids.md): its read-only checks, asked of whatever
/// host the client reaches, this Mac's or a droid's.
@Observable
final class HostDoctorModel {
    enum Phase {
        case checking
        case checked(HostDoctorReport)
        /// The host couldn't be asked: the message says why.
        case failed(String)
    }

    /// What the sheet calls the host: "This Mac", or a droid's name.
    let hostName: String
    private(set) var phase = Phase.checking
    @ObservationIgnored private let ask: @Sendable () async throws -> HostDoctorReport

    init(hostName: String, client: NativeHostClient) {
        self.hostName = hostName
        ask = { try await client.doctor() }
    }

    /// For previews and fixtures: a report without a host.
    init(hostName: String, report: @escaping @Sendable () async throws -> HostDoctorReport) {
        self.hostName = hostName
        ask = report
    }

    var report: HostDoctorReport? {
        if case .checked(let report) = phase { report } else { nil }
    }

    /// Runs the checks; a few seconds, since each CLI is asked for its version.
    func check() async {
        phase = .checking
        do {
            phase = .checked(try await ask())
        } catch {
            phase = .failed(error.localizedDescription)
        }
    }
}
