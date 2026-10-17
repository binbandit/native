import Foundation

/// Cuts a byte stream into newline-terminated lines, refusing any line longer than `maxLine` before
/// buffering it whole, so a runtime that's lost control can't make the host buffer without bound.
struct ScriptLineSplitter: Sendable {
    struct LineTooLong: LocalizedError {
        var errorDescription: String? { "The script runtime sent a line longer than the protocol allows" }
    }

    /// Long enough for the runtime's largest frame: a 1 MiB piece of text or tool input, JSON-escaped.
    static let standardMaxLine = 8 << 20

    let maxLine: Int
    private var buffer = Data()

    init(maxLine: Int = standardMaxLine) {
        self.maxLine = maxLine
    }

    /// The lines `data` completes, without their newlines.
    mutating func append(_ data: Data) throws -> [Data] {
        var lines: [Data] = []
        var rest = data[...]
        while let newline = rest.firstIndex(of: UInt8(ascii: "\n")) {
            let piece = rest[..<newline]
            guard buffer.count + piece.count <= maxLine else { throw LineTooLong() }
            lines.append(buffer + piece)
            buffer.removeAll(keepingCapacity: true)
            rest = rest[rest.index(after: newline)...]
        }
        guard buffer.count + rest.count <= maxLine else { throw LineTooLong() }
        buffer.append(contentsOf: rest)
        return lines
    }

    /// Whether a partial line is waiting for its newline.
    var hasPartialLine: Bool { !buffer.isEmpty }
}
