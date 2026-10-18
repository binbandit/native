import Foundation
import NativeDiagnostics
import Sentry

/// Transport adapter only. Native's telemetry gate owns consent and organization policy.
enum SentryTelemetry {
    private static var isDevelopmentBuild: Bool {
        let identifier = Bundle.main.bundleIdentifier ?? ""
        return identifier.contains(".dev.") || identifier.hasSuffix(".dev")
    }

    private static var cacheDirectory: URL? {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first?
            .appending(path: Bundle.main.bundleIdentifier ?? "Native")
            .appending(path: "SentryTelemetry", directoryHint: .isDirectory)
    }

    static var configuredDSN: String? {
        #if DEBUG
        return nil
        #else
        guard !isDevelopmentBuild,
            let dsn = Bundle.main.object(forInfoDictionaryKey: "NativeSentryDSN") as? String, !dsn.isEmpty
        else {
            return nil
        }
        return dsn
        #endif
    }

    /// Called only after the telemetry gate permits Native's destination.
    static func start(dsn: String) {
        #if !DEBUG
        guard !SentrySDK.isEnabled,
            let url = URL(string: dsn), url.scheme == "https", url.host != nil, url.user != nil,
            !isDevelopmentBuild
        else { return }
        SentrySDK.start { options in
            options.dsn = dsn
            let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.0.0"
            let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "0"
            options.releaseName = "native@\(version)+\(build)"
            if let cacheDirectory { options.cacheDirectoryPath = cacheDirectory.path }
            #if NATIVE_NIGHTLY
            options.environment = "nightly"
            #elseif NATIVE_BETA
            options.environment = "beta"
            #else
            options.environment = "production"
            #endif
            SentryPrivacy.configure(options, metrics: SentryTelemetryDestination.metricAllowlist)
        }
        #endif
    }

    /// The gate calls this as soon as consent is withdrawn or policy blocks Native's destination.
    static func stop() {
        SentrySDK.close()
        // An offline report from a previous opt-in must not be sent after consent is withdrawn.
        if let cacheDirectory { try? FileManager.default.removeItem(at: cacheDirectory) }
    }
}
