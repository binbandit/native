import CryptoKit
import Foundation

/// An immutable index whose exact bytes have passed signature and v1 validation.
public struct PluginCatalogIndex: Sendable {
    public let schema: Int
    public let plugins: [PluginCatalogEntry]

    private init(_ payload: Payload) {
        schema = payload.schema
        plugins = payload.plugins
    }

    /// The trusted key is the caller's 32-byte Ed25519 public key, never a key from the index.
    public static func verified(_ data: Data, signature: String, publicKey: Data) throws -> Self {
        guard let key = try? Curve25519.Signing.PublicKey(rawRepresentation: publicKey) else {
            throw PluginCatalogError.malformedPublicKey
        }
        guard let signature = Data(base64Encoded: signature.trimmingCharacters(in: .whitespacesAndNewlines)),
            signature.count == 64
        else { throw PluginCatalogError.malformedSignature }
        guard key.isValidSignature(signature, for: data) else { throw PluginCatalogError.signatureMismatch }
        // JSONDecoder also accepts UTF-16; the signed catalog contract requires UTF-8.
        guard String(data: data, encoding: .utf8) != nil else { throw PluginCatalogError.malformedJSON }
        do {
            let payload = try JSONDecoder().decode(Payload.self, from: data)
            var ids = Set<String>()
            for entry in payload.plugins where !ids.insert(entry.id).inserted {
                throw PluginCatalogError.duplicateID(entry.id)
            }
            return Self(payload)
        } catch let error as PluginCatalogError {
            throw error
        } catch {
            throw PluginCatalogError.malformedJSON
        }
    }

    private struct Payload: Decodable {
        let schema: Int
        let plugins: [PluginCatalogEntry]
        private enum CodingKeys: String, CodingKey { case schema, plugins }

        init(from decoder: any Decoder) throws {
            let values = try decoder.container(keyedBy: CodingKeys.self)
            schema = try values.decode(Int.self, forKey: .schema)
            guard schema == 1 else { throw PluginCatalogError.unsupportedSchema(schema) }
            plugins = try values.decode([PluginCatalogEntry].self, forKey: .plugins)
        }
    }
}
