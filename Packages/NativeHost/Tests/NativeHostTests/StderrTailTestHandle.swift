#if os(Linux)
import Foundation
import Synchronization

/// Holds a real readability callback in the reader while its owner releases the tail.
final class StderrTailTestHandle: FileHandle, @unchecked Sendable {
    final class Probe: Sendable {
        let entered = DispatchSemaphore(value: 0)
        let proceed = DispatchSemaphore(value: 0)
        let released = DispatchSemaphore(value: 0)
        let armed = Mutex(false)
        let closedBeforeRelease = Mutex(false)
    }

    let probe = Probe()

    override var fileDescriptor: Int32 {
        let shouldWait = probe.armed.withLock { armed in
            defer { armed = false }
            return armed
        }
        if shouldWait {
            probe.entered.signal()
            probe.proceed.wait()
        }
        return super.fileDescriptor
    }

    deinit {
        // Observe the explicit close before FileHandle's own deinit can close on deallocation.
        let wasClosed = super.fileDescriptor < 0
        probe.closedBeforeRelease.withLock { $0 = wasClosed }
        probe.released.signal()
    }
}
#endif
