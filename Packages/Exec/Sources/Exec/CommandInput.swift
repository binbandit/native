import Foundation

/// Input for one interactive command. Values travel over stdin, never command arguments or logs.
public final class CommandInput: Sendable {
    public let chunks: AsyncStream<Data>
    private let continuation: AsyncStream<Data>.Continuation

    public init() {
        (chunks, continuation) = AsyncStream.makeStream(bufferingPolicy: .bufferingOldest(8))
    }

    @discardableResult
    public func send(_ data: Data) -> Bool {
        guard data.count <= 16_384 else { return false }
        if case .enqueued = continuation.yield(data) { return true }
        return false
    }

    public func finish() { continuation.finish() }

    deinit { continuation.finish() }
}
