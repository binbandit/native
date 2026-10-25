import Foundation
import NativeHostProtocol
import Synchronization
import Testing

#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

@Suite(.timeLimit(.minutes(1)))
struct ByteChannelTests {
    /// Everything the other end of `descriptor` sends until it closes.
    private func received(on descriptor: Int32) async -> Data {
        var data = Data()
        for await chunk in ByteChannel.socket(descriptor, label: "other end").incoming() {
            data.append(chunk)
        }
        return data
    }

    @Test("Writes arrive in order, and what was queued still goes out when the channel closes")
    func orderedThroughClose() async throws {
        let (ours, theirs) = try UnixSocket.pair()
        let channel = ByteChannel.socket(ours, label: "test")
        var sent = Data()
        for index in 0..<200 {
            let chunk = Data("line \(index)\n".utf8)
            #expect(channel.write(chunk))
            sent.append(chunk)
        }
        // More than a socket buffers, so most of it is still queued at close.
        let large = Data((0..<(4 << 20)).map { UInt8(truncatingIfNeeded: $0) })
        #expect(channel.write(large))
        sent.append(large)
        channel.close()

        #expect(await received(on: theirs) == sent)
        #expect(!channel.write(Data("late".utf8)))
    }

    @Test("The other end hanging up ends what's read and closes the channel")
    func hangUp() async throws {
        let (ours, theirs) = try UnixSocket.pair()
        let channel = ByteChannel.socket(ours, label: "test")
        let closed = Mutex(false)
        channel.onClose { closed.withLock { $0 = true } }
        let incoming = channel.incoming()
        _ = "goodbye".withCString { write(theirs, $0, 7) }
        _ = close(theirs)

        var data = Data()
        for await chunk in incoming { data.append(chunk) }
        #expect(data == Data("goodbye".utf8))
        #expect(channel.isClosed)
        #expect(closed.withLock { $0 })
    }

    @Test("A released channel sends what it queued, then closes")
    func release() async throws {
        let (ours, theirs) = try UnixSocket.pair()
        var channel: ByteChannel? = ByteChannel.socket(ours, label: "test")
        channel?.write(Data("last words".utf8))
        channel = nil

        #expect(await received(on: theirs) == Data("last words".utf8))
    }

    @Test("A released channel whose reader stopped closes, though the other end stays open")
    func releaseAfterReaderStops() async throws {
        let (ours, theirs) = try UnixSocket.pair()
        defer { _ = close(theirs) }
        var channel: ByteChannel? = ByteChannel.socket(ours, label: "test")
        let incoming = try #require(channel?.incoming())
        let reading = Task {
            for await _ in incoming {}
        }
        reading.cancel()
        await reading.value
        channel = nil

        // The other end reads as ended once the channel has closed its descriptors. Without that the
        // read below would block, so a timed-out wait ends the test.
        var descriptor = pollfd(fd: theirs, events: Int16(POLLIN), revents: 0)
        try #require(poll(&descriptor, 1, 5_000) == 1)
        var byte: UInt8 = 0
        #expect(read(theirs, &byte, 1) == 0)
    }

    @Test("Waiting for a flush ends when the channel closes without sending")
    func flushEndsAtDiscard() async throws {
        let (ours, theirs) = try UnixSocket.pair()
        defer { _ = close(theirs) }
        let channel = ByteChannel.socket(ours, label: "test")
        // The other end never reads, so this can't all go out.
        #expect(channel.write(Data(count: 4 << 20)))
        channel.close(discardingPendingWrites: true)

        await channel.flushed()
        #expect(channel.isClosed)
    }

    @Test("A write that would pass the backlog limit is refused and closes the channel")
    func backlogLimit() throws {
        let (ours, theirs) = try UnixSocket.pair()
        defer { _ = close(theirs) }
        let channel = ByteChannel.socket(ours, label: "test")

        #expect(!channel.write(Data(count: ByteChannel.backlogLimit + 1)))
        #expect(channel.isClosed)
    }
}
