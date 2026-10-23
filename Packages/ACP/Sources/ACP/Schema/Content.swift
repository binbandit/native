import Foundation

/// Displayable content, shared with MCP's `ContentBlock`.
public enum ContentBlock: Hashable, Sendable {
    case text(String)
    case image(data: String, mimeType: String)
    case resourceLink(uri: String, name: String)
    case resource(uri: String, text: String?, mimeType: String? = nil)
    case resourceBlob(uri: String, mimeType: String?, blob: String)
    /// A block type this client doesn't understand yet, such as audio.
    case unsupported(type: String)

    public var text: String? {
        switch self {
        case .text(let text): text
        case .resource(_, let text, _): text
        default: nil
        }
    }
}

extension ContentBlock: Codable {
    private enum CodingKeys: String, CodingKey {
        case type, text, data, mimeType, uri, name, resource
    }

    private struct EmbeddedResource: Codable {
        let uri: String
        let text: String?
        var mimeType: String?
        var blob: String?
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)
        switch type {
        case "text":
            self = .text(try container.decode(String.self, forKey: .text))
        case "image":
            self = .image(
                data: try container.decode(String.self, forKey: .data),
                mimeType: try container.decode(String.self, forKey: .mimeType)
            )
        case "resource_link":
            self = .resourceLink(
                uri: try container.decode(String.self, forKey: .uri),
                name: try container.decode(String.self, forKey: .name)
            )
        case "resource":
            let resource = try container.decode(EmbeddedResource.self, forKey: .resource)
            if let blob = resource.blob {
                self = .resourceBlob(uri: resource.uri, mimeType: resource.mimeType, blob: blob)
            } else {
                self = .resource(uri: resource.uri, text: resource.text, mimeType: resource.mimeType)
            }
        default:
            self = .unsupported(type: type)
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .text(let text):
            try container.encode("text", forKey: .type)
            try container.encode(text, forKey: .text)
        case .image(let data, let mimeType):
            try container.encode("image", forKey: .type)
            try container.encode(data, forKey: .data)
            try container.encode(mimeType, forKey: .mimeType)
        case .resourceLink(let uri, let name):
            try container.encode("resource_link", forKey: .type)
            try container.encode(uri, forKey: .uri)
            try container.encode(name, forKey: .name)
        case .resource(let uri, let text, let mimeType):
            try container.encode("resource", forKey: .type)
            try container.encode(EmbeddedResource(uri: uri, text: text, mimeType: mimeType), forKey: .resource)
        case .resourceBlob(let uri, let mimeType, let blob):
            try container.encode("resource", forKey: .type)
            try container.encode(
                EmbeddedResource(uri: uri, text: nil, mimeType: mimeType, blob: blob), forKey: .resource)
        case .unsupported(let type):
            throw EncodingError.invalidValue(
                type,
                .init(codingPath: encoder.codingPath, debugDescription: "Cannot send unsupported content type \(type)"))
        }
    }
}
