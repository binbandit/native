import Foundation

/// A manifest's `celebrations`, decoded one entry at a time: a malformed entry becomes a problem the
/// catalogue lists, and the plugin's other celebrations, agents and servers still load.
public struct CelebrationContributions: Hashable, Sendable {
    public var valid: [CelebrationContribution]
    public var malformed: [CelebrationProblem]

    public init(_ valid: [CelebrationContribution] = [], malformed: [CelebrationProblem] = []) {
        self.valid = valid
        self.malformed = malformed
    }

    public var isEmpty: Bool { valid.isEmpty && malformed.isEmpty }
}

extension CelebrationContributions: Codable {
    public init(from decoder: any Decoder) throws {
        self.init()
        guard var container = try? decoder.unkeyedContainer() else {
            malformed = [CelebrationProblem(index: nil, id: nil, message: "\"celebrations\" should be a list.")]
            return
        }
        while !container.isAtEnd {
            let index = container.currentIndex
            // Entry's decoding never throws, so the container always moves on to the next element.
            switch try container.decode(Entry.self).result {
            case .success(let contribution): valid.append(contribution)
            case .failure(let failure):
                malformed.append(CelebrationProblem(index: index, id: failure.id, message: failure.message))
            }
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(valid)
    }

    private struct Entry: Decodable {
        struct Failure: Error {
            let id: String?
            let message: String
        }

        let result: Result<CelebrationContribution, Failure>

        private enum IDKey: String, CodingKey {
            case id
        }

        init(from decoder: any Decoder) {
            do {
                result = .success(try CelebrationContribution(from: decoder))
            } catch {
                let id = try? decoder.container(keyedBy: IDKey.self).decode(String.self, forKey: .id)
                result = .failure(Failure(id: id, message: CelebrationProblem.describe(error)))
            }
        }
    }
}

/// A celebration that couldn't be used, and why, in the user's terms.
public struct CelebrationProblem: Hashable, Sendable, CustomStringConvertible {
    /// Its position in the manifest's list, when the entry couldn't be read at all.
    public let index: Int?
    public let id: String?
    public let message: String
    /// The plugin it came from; set when the catalogue collects it.
    public var pluginID: String?

    public init(index: Int?, id: String?, message: String, pluginID: String? = nil) {
        self.index = index
        self.id = id
        self.message = message
        self.pluginID = pluginID
    }

    public var identifier: String {
        id ?? index.map { "Celebration \($0 + 1)" } ?? "Celebrations"
    }

    public var description: String {
        "\(identifier): \(message)"
    }

    public static func describe(_ error: any Error) -> String {
        func path(_ context: DecodingError.Context, _ key: (any CodingKey)? = nil) -> String {
            (context.codingPath + [key].compactMap { $0 })
                .map { $0.intValue.map { "[\($0)]" } ?? $0.stringValue }
                .joined(separator: ".")
                .replacingOccurrences(of: ".[", with: "[")
        }
        return switch error {
        case DecodingError.keyNotFound(let key, let context): "Missing \"\(path(context, key))\"."
        case DecodingError.typeMismatch(_, let context), DecodingError.valueNotFound(_, let context):
            "Wrong type at \"\(path(context))\"."
        case DecodingError.dataCorrupted(let context):
            context.codingPath.isEmpty
                ? context.debugDescription : "\(context.debugDescription) (at \"\(path(context))\")"
        default: error.localizedDescription
        }
    }
}
