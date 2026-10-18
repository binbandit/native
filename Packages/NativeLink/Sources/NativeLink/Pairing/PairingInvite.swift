import CryptoKit
import Foundation
import NativeHostProtocol

/// What the Mac's QR code carries: the host's public key (so the phone knows exactly whom it's
/// pairing with before it says anything), a one-time secret that expires in minutes, the host's name
/// and how to reach it. Encoded as a `nativecompanion://pair#…` link, so the iPhone's own Camera can
/// open the companion with it too.
public struct PairingInvite: Codable, Hashable, Sendable {
    public static let scheme = "nativecompanion"
    public static let currentVersion = 1

    public var version: Int
    /// The host instance: pairings are kept per `HostID`, so two Natives on one Mac are two hosts.
    public var hostID: HostID
    public var hostKey: LinkPublicKey
    /// 32 random bytes, used once. Never shown as text.
    public var secret: Data
    public var hostName: String
    public var expiresAt: Date
    public var addresses: [LinkAddress]

    public init(
        hostID: HostID, hostKey: LinkPublicKey, secret: Data, hostName: String, expiresAt: Date,
        addresses: [LinkAddress], version: Int = PairingInvite.currentVersion
    ) {
        self.version = version
        self.hostID = hostID
        self.hostKey = hostKey
        self.secret = secret
        self.hostName = hostName
        self.expiresAt = expiresAt
        self.addresses = addresses
    }

    public func isExpired(at now: Date) -> Bool {
        now >= expiresAt
    }

    /// The Noise pre-shared key the secret becomes, kept apart from any other use of the bytes.
    var preSharedKey: Data {
        Self.preSharedKey(secret: secret)
    }

    static func preSharedKey(secret: Data) -> Data {
        Data(SHA256.hash(data: Data("NativeLink invite v1".utf8) + secret))
    }

    public var url: URL {
        var components = URLComponents()
        components.scheme = Self.scheme
        components.host = "pair"
        components.fragment = (try? Self.encoder.encode(self))?.base64URLEncodedString()
        return components.url ?? URL(filePath: "/")
    }

    public enum ParseError: Error, LocalizedError, Equatable {
        case notAnInvite
        case newerVersion(Int)

        public var errorDescription: String? {
            switch self {
            case .notAnInvite: "That isn't a Native pairing code."
            case .newerVersion: "This code comes from a newer Native. Update this app to pair."
            }
        }
    }

    /// Reads a scanned or pasted link. Surrounding whitespace is ignored.
    public init(url text: String) throws {
        guard let components = URLComponents(string: text.trimmingCharacters(in: .whitespacesAndNewlines)),
            components.scheme == Self.scheme, components.host == "pair",
            let fragment = components.fragment, let data = Data(base64URLEncoded: fragment)
        else { throw ParseError.notAnInvite }
        let version = (try? JSONDecoder().decode(VersionOnly.self, from: data))?.version ?? 0
        guard version <= Self.currentVersion else { throw ParseError.newerVersion(version) }
        do {
            self = try Self.decoder.decode(Self.self, from: data)
        } catch {
            throw ParseError.notAnInvite
        }
    }

    private struct VersionOnly: Decodable {
        var version: Int

        private enum CodingKeys: String, CodingKey {
            case version = "v"
        }
    }

    private enum CodingKeys: String, CodingKey {
        case version = "v"
        case hostID = "i"
        case hostKey = "k"
        case secret = "s"
        case hostName = "n"
        case expiresAt = "x"
        case addresses = "a"
    }

    private static var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        encoder.dataEncodingStrategy = .custom { data, encoder in
            var container = encoder.singleValueContainer()
            try container.encode(data.base64URLEncodedString())
        }
        return encoder
    }

    private static var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        decoder.dataDecodingStrategy = .custom { decoder in
            let text = try decoder.singleValueContainer().decode(String.self)
            guard let data = Data(base64URLEncoded: text) else {
                throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Not base64url"))
            }
            return data
        }
        return decoder
    }
}
