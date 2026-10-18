import Foundation
import Sentry
import Testing

@testable import NativeDiagnostics

struct SentryPrivacyTests {
    @Test func disablesContentCollectors() {
        let options = Options()
        SentryPrivacy.configure(options)
        #expect(!options.sendDefaultPii)
        #expect(!options.enableAutoBreadcrumbTracking)
        #expect(!options.enableNetworkBreadcrumbs)
        #expect(!options.enableNetworkTracking)
        #expect(!options.enableCaptureFailedRequests)
        #expect(!options.enableAutoSessionTracking)
        #expect(!options.enableAutoPerformanceTracing)
        #expect(!options.enableMemoryIntrospection)
        #expect(!options.enableSwizzling)
        #expect(!options.enableLogs)
        #expect(!options.enableMetrics)
        #expect(options.maxAttachmentSize == 0)
        #expect(options.beforeBreadcrumb?(Breadcrumb()) == nil)
    }

    @Test func stripsContentButKeepsSymbolicationAddresses() throws {
        let secret = "PRIVATE_PROMPT /Users/person/project command output"
        let frame = Frame()
        frame.instructionAddress = "0x100012340"
        frame.imageAddress = "0x100000000"
        frame.fileName = secret
        frame.function = secret
        frame.package = secret
        frame.module = secret
        frame.contextLine = secret
        frame.vars = ["prompt": secret]
        frame.preContext = [secret]
        frame.postContext = [secret]
        let stack = SentryStacktrace(frames: [frame], registers: ["output": secret])
        let exception = Exception(value: secret, type: "EXC_BAD_ACCESS")
        exception.module = secret
        exception.stacktrace = stack
        let mechanism = Mechanism(type: secret)
        mechanism.handled = false
        mechanism.desc = secret
        mechanism.data = ["command": secret]
        exception.mechanism = mechanism
        let source = Event(level: .fatal)
        source.exceptions = [exception]
        source.message = SentryMessage(formatted: secret)
        source.extra = ["prompt": secret]
        source.tags = ["workspace": secret]
        source.context = ["work": ["output": secret]]
        source.transaction = secret
        source.serverName = secret
        source.logger = secret
        source.fingerprint = [secret]
        let image = DebugMeta()
        image.debugID = "0D33BFA3-7CF9-40CD-990E-5DE7E8CFC0F5"
        image.imageAddress = "0x100000000"
        image.codeFile = secret
        source.debugMeta = [image]
        let clean = try #require(SentryPrivacy.sanitize(source))
        let serialized = try JSONSerialization.data(withJSONObject: clean.serialize())
        let text = String(decoding: serialized, as: UTF8.self)
        #expect(!text.contains("PRIVATE_PROMPT"))
        #expect(!text.contains("/Users/"))
        #expect(text.contains("EXC_BAD_ACCESS"))
        #expect(text.contains("0x100012340"))
        #expect(text.contains("0D33BFA3"))
    }

    @Test func dropsMessagesAndTransactions() {
        #expect(SentryPrivacy.sanitize(Event(level: .error)) == nil)
        let transaction = Event(level: .error)
        transaction.type = "transaction"
        transaction.exceptions = [Exception(value: "text", type: "Error")]
        #expect(SentryPrivacy.sanitize(transaction) == nil)
    }

    @Test func replacesArbitraryErrorTypesAndMalformedAddresses() throws {
        let source = Event(level: .error)
        let frame = Frame()
        frame.instructionAddress = "/Users/person/private.swift"
        let exception = Exception(value: "private", type: "private prompt text")
        exception.stacktrace = SentryStacktrace(frames: [frame], registers: [:])
        source.exceptions = [exception]
        let clean = try #require(SentryPrivacy.sanitize(source))
        #expect(clean.exceptions?.first?.type == "NativeError")
        #expect(clean.exceptions?.first?.value == nil)
        #expect(clean.exceptions?.first?.stacktrace?.frames.first?.instructionAddress == nil)
    }
}
