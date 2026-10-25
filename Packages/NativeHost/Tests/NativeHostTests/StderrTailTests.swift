import Foundation
import NativeHostProtocol
import Testing

@testable import NativeHost

#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

@Suite(.timeLimit(.minutes(1)))
struct StderrTailTests {
    /// A tail on its own copy of the pipe's read end, as `AgentLaunch.spawn` makes one.
    private func tail(of pipe: Pipe) throws -> StderrTail {
        try StderrTail(reading: fcntl(pipe.fileHandleForReading.fileDescriptor, F_DUPFD_CLOEXEC, 0))
    }

    @Test("A diagnostic still in the pipe is in the snapshot", arguments: [false, true])
    func pendingDiagnostic(writerClosed: Bool) throws {
        let pipe = Pipe()
        let tail = try tail(of: pipe)
        try pipe.fileHandleForWriting.write(contentsOf: Data("startup diagnostic\n".utf8))
        if writerClosed { try pipe.fileHandleForWriting.close() }

        #expect(tail.text == "startup diagnostic\n")
        #expect(tail.text == "startup diagnostic\n")
    }

    @Test("An empty pipe with a live writer does not block a diagnostic snapshot")
    func emptyOpenPipe() throws {
        let pipe = Pipe()
        let tail = try tail(of: pipe)

        #expect(tail.text.isEmpty)
        try pipe.fileHandleForWriting.write(contentsOf: Data("later diagnostic".utf8))
        #expect(tail.text == "later diagnostic")
    }

    @Test("Diagnostic snapshots retain only the last 16 KiB across reads")
    func boundedTail() throws {
        let pipe = Pipe()
        let tail = try tail(of: pipe)
        var written = Data()
        for byte in UInt8(65)..<85 {
            let chunk = Data(repeating: byte, count: 1024)
            try pipe.fileHandleForWriting.write(contentsOf: chunk)
            written.append(chunk)
            #expect(tail.text == String(decoding: written.suffix(16 * 1024), as: UTF8.self))
        }
    }

    @Test("An agent writing far more than a pipe holds never waits for a snapshot")
    func chattyWriter() throws {
        let pipe = Pipe()
        let tail = try tail(of: pipe)
        // Several times what a pipe buffers: these blocking writes finish only if the tail drains.
        let written = Data((0..<256 * 1024).map { UInt8(65 + $0 % 26) })
        try pipe.fileHandleForWriting.write(contentsOf: written)
        try pipe.fileHandleForWriting.close()

        #expect(tail.text == String(decoding: written.suffix(16 * 1024), as: UTF8.self))
    }

    @Test("Releasing the tail closes its end even while something still holds the other open")
    func releaseCloses() throws {
        let (writer, reader) = try UnixSocket.pair()
        defer { _ = close(writer) }
        var tail: StderrTail? = try StderrTail(reading: reader)
        try #require(tail?.text.isEmpty == true)

        tail = nil
        // The writer's end reads as ended once the tail's end is closed.
        var descriptor = pollfd(fd: writer, events: Int16(POLLIN), revents: 0)
        #expect(poll(&descriptor, 1, 5_000) == 1)
        var byte: UInt8 = 0
        #expect(read(writer, &byte, 1) == 0)
    }
}
