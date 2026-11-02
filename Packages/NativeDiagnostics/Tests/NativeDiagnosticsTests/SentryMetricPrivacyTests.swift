import Foundation
@_spi(Private) @preconcurrency import Sentry
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

struct SentryMetricAllowlistTests {
    let allowlist = SentryMetricAllowlist(
        counts: ["native.session.started"], distributions: ["native.launch.duration_ms"],
        tagKeys: ["agent.id", "agent.version"])

    private func metric(
        _ name: String, _ value: SentryMetricValue, unit: SentryUnit? = nil,
        attributes: [String: SentryAttributeContent]
    ) -> SentryMetric {
        SentryMetric(
            timestamp: .now, traceId: SentryId(), name: name, value: value, unit: unit, attributes: attributes)
    }

    @Test func keepsOnlyAllowlistedTokenTags() throws {
        let clean = try #require(
            SentryPrivacy.sanitize(
                metric(
                    "native.session.started", .counter(1),
                    attributes: [
                        "agent.id": .string("codex"), "agent.version": .string("0.93.0"),
                        "prompt": .string("private"), "sentry.environment": .string("production"),
                    ]), allowlist: allowlist))
        #expect(clean.attributes == ["agent.id": .string("codex"), "agent.version": .string("0.93.0")])
    }

    @Test func dropsFreeTextInAllowlistedTags() throws {
        let clean = try #require(
            SentryPrivacy.sanitize(
                metric(
                    "native.session.started", .counter(1), attributes: ["agent.id": .string("/Users/person/My Agent")]),
                allowlist: allowlist))
        #expect(clean.attributes.isEmpty)
    }

    @Test func dropsMetricsOutsideTheAllowlist() {
        #expect(
            SentryPrivacy.sanitize(metric("native.prompt.sent", .counter(1), attributes: [:]), allowlist: allowlist)
                == nil)
        #expect(
            SentryPrivacy.sanitize(metric("native.session.started", .gauge(1), attributes: [:]), allowlist: allowlist)
                == nil)
        #expect(
            SentryPrivacy.sanitize(
                metric("native.launch.duration_ms", .distribution(-1), unit: .millisecond, attributes: [:]),
                allowlist: allowlist) == nil)
    }
}
