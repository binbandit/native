import Foundation

/// Assembles server-sent events from the lines of an event stream: `event:` names one, `data:`
/// lines carry its payload, and a blank line ends it.
struct ServerSentEvents {
    struct Event: Hashable {
        var name: String
        var data: String
    }

    private var name: String?
    private var data: [String] = []

    /// The event `line` completes, if it's the blank line ending one.
    mutating func feed(_ line: String) -> Event? {
        if line.isEmpty {
            defer {
                name = nil
                data = []
            }
            guard !data.isEmpty else { return nil }
            return Event(name: name ?? "message", data: data.joined(separator: "\n"))
        }
        if line.hasPrefix(":") { return nil }
        let (field, value) = Self.split(line)
        switch field {
        case "event": name = value
        case "data": data.append(value)
        default: break
        }
        return nil
    }

    /// `field: value`, where one space after the colon isn't part of the value.
    private static func split(_ line: String) -> (String, String) {
        guard let colon = line.firstIndex(of: ":") else { return (line, "") }
        var value = line[line.index(after: colon)...]
        if value.hasPrefix(" ") { value = value.dropFirst() }
        return (String(line[..<colon]), String(value))
    }
}

/// The lines of a byte stream, blank ones included (which `AsyncBytes.lines` drops, and event
/// streams need), split at `\n` with a trailing `\r` removed.
struct LineSequence<Bytes: AsyncSequence>: AsyncSequence where Bytes.Element == UInt8 {
    typealias Element = String

    let bytes: Bytes

    struct AsyncIterator: AsyncIteratorProtocol {
        var base: Bytes.AsyncIterator
        var isDone = false

        mutating func next() async throws -> String? {
            guard !isDone else { return nil }
            var line = [UInt8]()
            while let byte = try await base.next() {
                if byte == UInt8(ascii: "\n") {
                    if line.last == UInt8(ascii: "\r") { line.removeLast() }
                    return String(decoding: line, as: UTF8.self)
                }
                line.append(byte)
            }
            isDone = true
            return line.isEmpty ? nil : String(decoding: line, as: UTF8.self)
        }
    }

    func makeAsyncIterator() -> AsyncIterator {
        AsyncIterator(base: bytes.makeAsyncIterator())
    }
}
