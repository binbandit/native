import Foundation

extension String {
    /// The text without terminal escape sequences (colors, cursor moves, window titles) or other
    /// control characters, for showing what an agent wrote to its terminal, such as its stderr, as
    /// plain text. Newlines and tabs stay.
    public var withoutTerminalEscapes: String {
        var plain = String.UnicodeScalarView()
        var scalars = unicodeScalars[...]
        while let scalar = scalars.popFirst() {
            if scalar == "\u{1B}" {
                switch scalars.popFirst() {
                case "[":
                    // CSI: parameter and intermediate bytes, ended by one final byte (@ through ~).
                    while let byte = scalars.popFirst(), !(0x40...0x7E).contains(byte.value) {}
                case "]":
                    // OSC: ended by BEL or by ESC \.
                    while let byte = scalars.popFirst() {
                        if byte == "\u{07}" { break }
                        if byte == "\u{1B}" {
                            _ = scalars.popFirst()
                            break
                        }
                    }
                case let byte? where (0x20...0x2F).contains(byte.value):
                    // nF (`ESC ( B`): more intermediate bytes, ended by one final byte.
                    while let byte = scalars.popFirst(), !(0x30...0x7E).contains(byte.value) {}
                default:
                    // A two-character sequence, or an escape at the very end.
                    break
                }
            } else if scalar.properties.generalCategory != .control || scalar == "\n" || scalar == "\t" {
                plain.append(scalar)
            }
        }
        return String(plain)
    }
}
