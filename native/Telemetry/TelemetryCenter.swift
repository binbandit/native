import Foundation
import NativePolicy
import NativeTelemetry
import Observation

/// Decides where telemetry goes and keeps `Telemetry.pipeline` in step: Native's own destination
/// only when the user has opted in (or the organization forces it on) and the organization hasn't
/// forced it off; the organization's collectors whenever its policy lists them.
@MainActor
@Observable
final class TelemetryCenter {
    static let shared = TelemetryCenter()

    enum Consent: String {
        case undecided, granted, declined
    }

    private(set) var consent: Consent {
        didSet { defaults.set(consent.rawValue, forKey: Self.consentKey) }
    }
    private(set) var installationID: UUID
    /// Where events go right now.
    private(set) var activeDestinations: [TelemetryDestinationID] = []

    @ObservationIgnored let sentLog: TelemetrySentLog
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let ids: TelemetryInstallationID
    @ObservationIgnored private var agentVersion: (AgentDefinition.ID) -> String? = { _ in nil }
    @ObservationIgnored private var policyWatch: Task<Void, Never>?

    private static let consentKey = "telemetry.native.consent"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        ids = TelemetryInstallationID(defaults: defaults)
        installationID = ids.current
        consent = defaults.string(forKey: Self.consentKey).flatMap(Consent.init(rawValue:)) ?? .undecided
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        sentLog = TelemetrySentLog(url: support.appending(path: "Native/Telemetry/sent.jsonl"))
    }

    /// Whether this build has a destination for Native's own telemetry.
    var isNativeDestinationAvailable: Bool {
        NativeTelemetryDestination.factory != nil
    }

    /// Who decides about Native's own telemetry, per the organization's policy.
    var nativeMode: NativePolicy.Telemetry.NativeMode {
        PolicyCenter.shared.policy.telemetry.native
    }

    var isNativeEnabled: Bool {
        guard isNativeDestinationAvailable else { return false }
        return switch nativeMode {
        case .on: true
        case .off: false
        case .user: consent == .granted
        }
    }

    var organizationEndpoints: [TelemetryEndpoint] {
        PolicyCenter.shared.policy.telemetry.endpoints
    }

    /// Starts the gate; call once, at launch, from the first window.
    func start(agentVersion: @escaping (AgentDefinition.ID) -> String?) {
        guard policyWatch == nil else { return }
        self.agentVersion = agentVersion
        let launchDuration = Self.timeSinceProcessStart()
        policyWatch = Task { [weak self] in
            guard let self else { return }
            await Telemetry.pipeline.configure(
                resource: resource, conditions: TelemetrySendingWindow(), log: sentLog)
            await apply()
            if let launchDuration {
                Telemetry.record(.appLaunched(launchDuration: launchDuration))
            }
            TelemetryHangWatchdog.start()
            // Re-apply whenever the organization changes what it allows.
            for await _ in Observations({ @MainActor in PolicyCenter.shared.policy.telemetry }) {
                await apply()
            }
        }
    }

    func setConsent(_ granted: Bool) {
        consent = granted ? .granted : .declined
        Task { await apply() }
    }

    func resetInstallationID() {
        installationID = ids.rotate()
        let id = installationID
        Task { await Telemetry.pipeline.setInstallationID(id) }
    }

    func version(of agent: AgentDefinition.ID) -> String? {
        agentVersion(agent)
    }

    private func apply() async {
        var destinations: [any TelemetryDestination] = []
        if isNativeEnabled, let native = NativeTelemetryDestination.factory?() {
            destinations.append(native)
        }
        destinations += organizationEndpoints.map {
            OTLPLogDestination(url: $0.url, headers: $0.headers, attributes: $0.attributes)
        }
        await Telemetry.pipeline.setDestinations(destinations)
        // Consent can change while Native isn't running, with a crash still cached on disk.
        if !isNativeEnabled { SentryTelemetry.stop() }
        activeDestinations = await Telemetry.pipeline.activeDestinations
    }

    private var resource: TelemetryResource {
        let info = Bundle.main.infoDictionary ?? [:]
        let os = ProcessInfo.processInfo.operatingSystemVersion
        return TelemetryResource(
            installationID: installationID,
            appVersion: (info["CFBundleShortVersionString"] as? String).flatMap(TelemetryVersion.init),
            osVersion: TelemetryVersion("\(os.majorVersion).\(os.minorVersion).\(os.patchVersion)"))
    }

    /// From the process starting to now, which at the first window is the launch time.
    private static func timeSinceProcessStart() -> Duration? {
        #if os(macOS)
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.stride
        var name: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, getpid()]
        guard sysctl(&name, 4, &info, &size, nil, 0) == 0 else { return nil }
        let start = info.kp_proc.p_un.__p_starttime
        let started = Date(timeIntervalSince1970: Double(start.tv_sec) + Double(start.tv_usec) / 1_000_000)
        return .milliseconds(Int64(Date.now.timeIntervalSince(started) * 1000))
        #else
        return nil
        #endif
    }
}
