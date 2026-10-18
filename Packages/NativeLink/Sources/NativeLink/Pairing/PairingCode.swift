import CryptoKit
import Foundation

/// The six-character code the Mac shows beside the QR code, for when the camera can't be used. It
/// doesn't carry the host's key, so pairing by code finds the host with Bonjour and relies on the
/// verification code both screens show (`VerificationCode`) before the Mac trusts the device. Its 30
/// bits only have to survive three guesses: a wrong code three times ends the pairing window.
public struct PairingCode: Hashable, Sendable, CustomStringConvertible {
    public static let length = 6

    /// Upper-case Crockford base32.
    public let rawValue: String

    public init() {
        var generator = SystemRandomNumberGenerator()
        rawValue = String((0..<Self.length).map { _ in Base32.alphabet[Int(generator.next(upperBound: UInt8(32)))] })
    }

    /// Reads what someone typed: case, spaces and dashes don't matter, and the letters Crockford
    /// leaves out read as the digits they look like.
    public init?(typed text: String) {
        let mapped = text.uppercased().compactMap { character -> Character? in
            switch character {
            case "O": "0"
            case "I", "L": "1"
            case " ", "-": nil
            default: character
            }
        }
        guard mapped.count == Self.length, mapped.allSatisfy(Base32.alphabet.contains) else { return nil }
        rawValue = String(mapped)
    }

    /// "K7Q 4MX": two groups of three, as the Mac shows it.
    public var description: String {
        "\(rawValue.prefix(3)) \(rawValue.suffix(3))"
    }

    var preSharedKey: Data {
        Data(SHA256.hash(data: Data("NativeLink pairing code v1".utf8) + Data(rawValue.utf8)))
    }
}

/// Six digits both screens show while the Mac asks whether to trust a device: derived from the
/// Noise handshake hash, so a machine in the middle would make the two screens disagree.
public struct VerificationCode: Hashable, Sendable, Codable, CustomStringConvertible {
    public let digits: String

    init(handshakeHash: Data) {
        let digest = Data(SHA256.hash(data: Data("NativeLink verification v1".utf8) + handshakeHash))
        let number = digest.prefix(4).reduce(UInt32(0)) { ($0 << 8) | UInt32($1) } % 1_000_000
        digits = String(format: "%06u", number)
    }

    public init(digits: String) {
        self.digits = digits
    }

    public init(from decoder: any Decoder) throws {
        digits = try decoder.singleValueContainer().decode(String.self)
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(digits)
    }

    /// "482 913".
    public var description: String {
        "\(digits.prefix(3)) \(digits.suffix(3))"
    }
}
