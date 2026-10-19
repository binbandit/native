import Foundation

/// A script's output as it arrives, standard output and error together in the order they came, as a
/// terminal shows them. Capped, so a chatty script can't use up memory: past the cap the oldest lines
/// go, and `droppedBytes` says how much.
public struct TaskScriptOutput: Hashable, Sendable {
    public static let defaultLimit = 256 * 1024

    public private(set) var data = Data()
    public private(set) var droppedBytes = 0
    private let limit: Int

    public init(limit: Int = Self.defaultLimit) {
        self.limit = limit
    }

    public var isEmpty: Bool { data.isEmpty }

    public mutating func append(_ chunk: Data) {
        data.append(chunk)
        guard data.count > limit else { return }
        var cut = data.count - limit
        // Start at a line, so nothing begins halfway through a character.
        if let newline = data[(data.startIndex + cut)...].firstIndex(of: UInt8(ascii: "\n")) {
            cut = newline + 1 - data.startIndex
        }
        droppedBytes += cut
        data = Data(data.dropFirst(cut))
    }

    /// Adds a line of Native's own, such as which script starts next.
    public mutating func appendLine(_ line: String) {
        if let last = data.last, last != UInt8(ascii: "\n") {
            append(Data("\n".utf8))
        }
        append(Data((line + "\n").utf8))
    }

    /// The output as plain text: each line a progress bar redrew with carriage returns as it last
    /// looked, without terminal colors and cursor moves.
    public var text: String {
        // Swift reads `\r\n` as one character, so it's made a plain newline before splitting.
        String(decoding: data, as: UTF8.self).replacingOccurrences(of: "\r\n", with: "\n")
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { line in
                let shown = line.split(separator: "\r", omittingEmptySubsequences: false).last ?? ""
                return Self.withoutEscapes(shown)
            }
            .joined(separator: "\n")
    }

    /// The last `count` lines with something on them, for a failure's summary.
    public func lastLines(_ count: Int) -> [String] {
        Array(
            text.split(separator: "\n").map(String.init)
                .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
                .suffix(count))
    }

    /// A line without escape sequences (CSI such as colors, OSC such as titles) or other control
    /// characters but tabs.
    private static func withoutEscapes(_ line: Substring) -> String {
        var plain = String.UnicodeScalarView()
        var scalars = line.unicodeScalars[...]
        while let scalar = scalars.popFirst() {
            if scalar == "\u{1B}" {
                switch scalars.popFirst() {
                case "[":
                    // Parameter and intermediate bytes, ended by one final byte (@ through ~).
                    while let byte = scalars.popFirst(), !(0x40...0x7E).contains(byte.value) {}
                case "]":
                    // Ended by BEL or by ESC \.
                    while let byte = scalars.popFirst(), byte != "\u{07}" {
                        if byte == "\u{1B}" {
                            _ = scalars.popFirst()
                            break
                        }
                    }
                default:
                    break
                }
            } else if scalar.properties.generalCategory != .control || scalar == "\t" {
                plain.append(scalar)
            }
        }
        return String(plain)
    }
}
