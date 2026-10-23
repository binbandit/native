#if os(Linux)
import Foundation
import Synchronization

/// Holds a real readability callback in the reader while its owner releases the tail.
final class StderrTailTestHandle: FileHandle, @unchecked Sendable {
    private static let callbackKey = "Native.StderrTailTests.inCallback"
    let entered = DispatchSemaphore(value: 0)
    let proceed = DispatchSemaphore(value: 0)
    let closed = DispatchSemaphore(value: 0)
    let armed = Mutex(false)
    let closedInsideCallback = Mutex(false)

    override var fileDescriptor: Int32 {
        let shouldWait = armed.withLock { armed in
            defer { armed = false }
            return armed
        }
        if shouldWait {
            entered.signal()
            proceed.wait()
        }
        return super.fileDescriptor
    }

    override var readabilityHandler: (@Sendable (FileHandle) -> Void)? {
        get { super.readabilityHandler }
        set {
            guard let handler = newValue else {
                super.readabilityHandler = nil
                return
            }
            super.readabilityHandler = { handle in
                Thread.current.threadDictionary[Self.callbackKey] = true
                defer { Thread.current.threadDictionary.removeObject(forKey: Self.callbackKey) }
                handler(handle)
            }
        }
    }

    override func close() throws {
        closedInsideCallback.withLock {
            $0 = Thread.current.threadDictionary[Self.callbackKey] as? Bool == true
        }
        try super.close()
        closed.signal()
    }
}
#endif
