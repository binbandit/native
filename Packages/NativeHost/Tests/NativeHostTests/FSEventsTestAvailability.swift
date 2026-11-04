import Foundation
import Testing

#if os(macOS)
import CoreServices
import Synchronization
#endif

/// Some service-launched CI runners start streams successfully but never receive callbacks,
/// even outside temporary directories. Probe CoreServices independently of the watcher under test.
enum FSEventsTestAvailability {
    static var requiresDelivery: ConditionTrait {
        .enabled("An independent CoreServices probe received no FSEvents in this environment") {
            try await available.value
        }
    }

    private static let available = Task<Bool, any Error> {
        #if os(macOS)
        try await probe()
        #else
        true
        #endif
    }

    #if os(macOS)
    private static func probe() async throws -> Bool {
        let manager = FileManager.default
        let folder = manager.temporaryDirectory.appending(path: "fsevents-probe-\(UUID().uuidString)")
        try manager.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? manager.removeItem(at: folder) }
        let context = Unmanaged.passRetained(Delivery())
        defer { context.release() }
        var streamContext = FSEventStreamContext(
            version: 0, info: context.toOpaque(), retain: nil, release: nil, copyDescription: nil)
        guard
            let stream = FSEventStreamCreate(
                kCFAllocatorDefault,
                { _, info, count, _, _, _ in
                    guard let info, count > 0 else { return }
                    Unmanaged<Delivery>.fromOpaque(info).takeUnretainedValue().received.withLock { $0 = true }
                },
                &streamContext,
                [folder.resolvingSymlinksInPath().path(percentEncoded: false)] as CFArray,
                FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
                0.05,
                FSEventStreamCreateFlags(kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagNoDefer)
            )
        else {
            return false
        }
        let queue = DispatchQueue(label: "Native.Tests.FSEventsProbe")
        FSEventStreamSetDispatchQueue(stream, queue)
        defer {
            FSEventStreamInvalidate(stream)
            queue.sync {}
            FSEventStreamRelease(stream)
        }
        guard FSEventStreamStart(stream) else { return false }
        defer { FSEventStreamStop(stream) }

        let deadline = ContinuousClock.now + .seconds(5)
        while ContinuousClock.now < deadline {
            try Data(UUID().uuidString.utf8).write(to: folder.appending(path: "probe.txt"))
            if context.takeUnretainedValue().received.withLock({ $0 }) { return true }
            try await Task.sleep(for: .milliseconds(50))
        }
        return context.takeUnretainedValue().received.withLock { $0 }
    }

    private final class Delivery: Sendable {
        let received = Mutex(false)
    }
    #endif
}
