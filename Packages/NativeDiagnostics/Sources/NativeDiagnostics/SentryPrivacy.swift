import Foundation
import Sentry

/// Rebuild reports from an allowlist: SDK additions cannot silently introduce user content.
public enum SentryPrivacy {
    public static func configure(_ options: Options) {
        options.sendDefaultPii = false
        options.enableAutoBreadcrumbTracking = false
        options.enableNetworkBreadcrumbs = false
        options.maxBreadcrumbs = 0
        options.beforeBreadcrumb = { _ in nil }
        options.enableAutoPerformanceTracing = false
        options.enableNetworkTracking = false
        options.enableCaptureFailedRequests = false
        options.enableFileIOTracing = false
        options.enableCoreDataTracing = false
        options.enableSwizzling = false
        options.enableDataSwizzling = false
        options.enableFileManagerSwizzling = false
        options.enableAutoSessionTracking = false
        options.enableWatchdogTerminationTracking = false
        options.enableMemoryIntrospection = false
        options.enableMetricKit = false
        options.enableMetricKitRawPayload = false
        options.enableLogs = false
        options.enableMetrics = false
        options.beforeSendLog = { _ in nil }
        options.beforeSendMetric = { _ in nil }
        options.beforeSendSpan = { _ in nil }
        options.sendClientReports = false
        options.maxAttachmentSize = 0
        options.shutdownTimeInterval = 0
        options.tracesSampleRate = 0
        let releaseName = options.releaseName
        let distribution = options.dist
        let environment = options.environment
        options.beforeSend = { source in
            guard let event = sanitize(source) else { return nil }
            event.releaseName = safeVersion(releaseName)
            event.dist = safeVersion(distribution)
            event.environment = environment
            return event
        }
        #if os(iOS) || os(tvOS) || os(visionOS)
        options.attachScreenshot = false
        options.attachViewHierarchy = false
        options.enableUserInteractionTracing = false
        options.enableUIViewControllerTracing = false
        options.reportAccessibilityIdentifier = false
        options.sessionReplay.sessionSampleRate = 0
        options.sessionReplay.onErrorSampleRate = 0
        #endif
    }

    public static func sanitize(_ source: Event) -> Event? {
        guard source.type == nil || source.type == "error" || source.type == "default",
            let exceptions = source.exceptions, !exceptions.isEmpty
        else { return nil }

        let event = Event(level: source.level == .fatal ? .fatal : .error)
        event.eventId = source.eventId
        event.timestamp = source.timestamp
        event.platform = "cocoa"
        event.exceptions = exceptions.map { original in
            let exception = Exception(value: nil, type: exceptionType(original.type))
            exception.threadId = original.threadId
            exception.stacktrace = stacktrace(original.stacktrace)
            if let originalMechanism = original.mechanism {
                let mechanism = Mechanism(type: originalMechanism.handled == false ? "crash" : "generic")
                mechanism.handled = originalMechanism.handled
                exception.mechanism = mechanism
            }
            return exception
        }
        event.threads = source.threads?.map { original in
            let thread = SentryThread(threadId: original.threadId)
            thread.crashed = original.crashed
            thread.current = original.current
            thread.isMain = original.isMain
            thread.stacktrace = stacktrace(original.stacktrace)
            return thread
        }
        event.stacktrace = stacktrace(source.stacktrace)
        event.debugMeta = source.debugMeta?.compactMap { original in
            guard let id = original.debugID, UUID(uuidString: id) != nil else { return nil }
            let image = DebugMeta()
            image.type = "macho"
            image.codeFile = "image"
            image.debugID = id
            image.imageAddress = address(original.imageAddress)
            image.imageVmAddress = address(original.imageVmAddress)
            image.imageSize = original.imageSize
            // UUID and load addresses suffice for symbolication; binary paths reveal workspaces.
            return image
        }
        return event
    }

    private static func stacktrace(_ source: SentryStacktrace?) -> SentryStacktrace? {
        guard let source else { return nil }
        return SentryStacktrace(
            frames: source.frames.map { original in
                let frame = Frame()
                frame.instructionAddress = address(original.instructionAddress)
                frame.imageAddress = address(original.imageAddress)
                frame.symbolAddress = address(original.symbolAddress)
                frame.inApp = original.inApp
                frame.stackStart = original.stackStart
                return frame
            }, registers: [:])
    }

    private static func address(_ value: String?) -> String? {
        guard let value, value.hasPrefix("0x"), value.count <= 18,
            UInt64(value.dropFirst(2), radix: 16) != nil
        else { return nil }
        return value
    }

    private static func safeVersion(_ value: String?) -> String? {
        guard let value, value.count <= 150,
            value.range(of: #"^[a-zA-Z0-9.@+_-]+$"#, options: .regularExpression) != nil
        else { return nil }
        return value
    }

    private static func exceptionType(_ value: String?) -> String {
        let allowed = [
            "EXC_BAD_ACCESS", "EXC_BAD_INSTRUCTION", "EXC_ARITHMETIC", "EXC_BREAKPOINT",
            "EXC_CRASH", "EXC_GUARD", "EXC_RESOURCE", "SIGABRT", "SIGBUS", "SIGFPE", "SIGILL",
            "SIGSEGV", "SIGTRAP", "App Hanging", "AppHang", "NSInvalidArgumentException",
            "NSRangeException", "NSInternalInconsistencyException", "NativeSentryVerification",
        ]
        return value.flatMap { allowed.contains($0) ? $0 : nil } ?? "NativeError"
    }
}
