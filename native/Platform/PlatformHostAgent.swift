import Foundation
import NativeHostProtocol

#if os(macOS)
import NativeHostClient
import ServiceManagement
#endif

/// The launchd agent that runs this build's background host, for `HostRegistration`: a login item
/// (`SMAppService`) that starts it at every login, or, for development builds, a job for this login
/// session only. Mac only: an iPad runs no host of its own, so there the login item is never
/// registered and starting or stopping either does nothing.
struct PlatformHostAgent {
    /// `SMAppService.Status`, which iPadOS doesn't have.
    enum Status: Equatable {
        case notRegistered
        case enabled
        /// The user turned Native off under Login Items › Allow in the Background.
        case requiresApproval
        case notFound
    }

    let plistName: String
    let bundledPlist: URL
    let location: HostLocation

    var loginItemStatus: Status {
        #if os(macOS)
        switch loginItem.status {
        case .notRegistered: .notRegistered
        case .enabled: .enabled
        case .requiresApproval: .requiresApproval
        case .notFound: .notFound
        @unknown default: .notFound
        }
        #else
        .notRegistered
        #endif
    }

    func registerLoginItem() throws {
        #if os(macOS)
        try loginItem.register()
        #endif
    }

    func unregisterLoginItem() async throws {
        #if os(macOS)
        try await loginItem.unregister()
        #endif
    }

    func startSessionJob() async throws {
        #if os(macOS)
        try await sessionJob.start()
        #endif
    }

    func stopSessionJob() async throws {
        #if os(macOS)
        try await sessionJob.stop()
        #endif
    }

    #if os(macOS)
    private var loginItem: SMAppService {
        .agent(plistName: plistName)
    }

    private var sessionJob: LaunchdSessionJob {
        LaunchdSessionJob(bundledPlist: bundledPlist, appBundle: Bundle.main.bundleURL, location: location)
    }
    #endif
}
