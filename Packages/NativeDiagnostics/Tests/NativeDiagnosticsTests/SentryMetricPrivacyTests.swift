import Foundation
@preconcurrency import Sentry
import Testing

@testable import NativeDiagnostics

struct SentryMetricPrivacyTests {
    @Test @MainActor func filtersMetricsAfterSDKEnrichment() throws {
        let cache = FileManager.default.temporaryDirectory.appending(path: "sentry-metric-test-\(UUID())")
        defer {
            SentrySDK.close()
            try? FileManager.default.removeItem(at: cache)
        }
        let options = Options()
        options.dsn = "https://public@example.invalid/1"
        options.cacheDirectoryPath = cache.path
        options.enableCrashHandler = false
        SentryPrivacy.configure(options)
        let filter = try #require(options.beforeSendMetric)
        var callbacks = 0
        options.beforeSendMetric = { metric in
            callbacks += 1
            let clean = filter(metric)
            if metric.name == "native.launch.duration_ms" {
                #expect(clean?.attributes.isEmpty == true)
                #expect(clean?.spanId == nil)
                #expect(clean?.value == .distribution(812))
            } else {
                #expect(clean == nil)
            }
            // This test exercises the real capture path without sending anything.
            return nil
        }
        SentrySDK.start(options: options)
        SentrySDK.metrics.distribution(
            key: "native.launch.duration_ms", value: 812, unit: .millisecond,
            attributes: ["prompt": "private prompt", "path": "/Users/person/project"])
        SentrySDK.metrics.distribution(key: "private command", value: 1, unit: .millisecond)
        #expect(callbacks == 2)
    }
}
