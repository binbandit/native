import Foundation
import Testing

@testable import NativeHost

@Suite(.timeLimit(.minutes(1)))
struct StderrTailTests {
    @Test("A diagnostic is available before the stderr callback runs", arguments: [false, true])
    func pendingDiagnostic(writerClosed: Bool) throws {
        let pipe = Pipe()
        let tail = try StderrTail(reading: pipe.fileHandleForReading)
        // Force the ordering that stdout EOF exposed on Linux: the snapshot comes first.
        pipe.fileHandleForReading.readabilityHandler = nil
        try pipe.fileHandleForWriting.write(contentsOf: Data("startup diagnostic\n".utf8))
        if writerClosed { try pipe.fileHandleForWriting.close() }

        #expect(tail.text == "startup diagnostic\n")
        #expect(tail.text == "startup diagnostic\n")
    }

    @Test("An empty pipe with a live writer does not block a diagnostic snapshot")
    func emptyOpenPipe() throws {
        let pipe = Pipe()
        let tail = try StderrTail(reading: pipe.fileHandleForReading)
        pipe.fileHandleForReading.readabilityHandler = nil

        #expect(tail.text.isEmpty)
        try pipe.fileHandleForWriting.write(contentsOf: Data("later diagnostic".utf8))
        #expect(tail.text == "later diagnostic")
    }

    @Test("Diagnostic snapshots retain only the last 16 KiB across reads")
    func boundedTail() throws {
        let pipe = Pipe()
        let tail = try StderrTail(reading: pipe.fileHandleForReading)
        pipe.fileHandleForReading.readabilityHandler = nil
        var written = Data()
        for byte in UInt8(65)..<85 {
            let chunk = Data(repeating: byte, count: 1024)
            try pipe.fileHandleForWriting.write(contentsOf: chunk)
            written.append(chunk)
            #expect(tail.text == String(decoding: written.suffix(16 * 1024), as: UTF8.self))
        }
    }
}
