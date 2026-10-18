import Foundation

/// The kinds of appearance contribution a plugin manifest can carry.
public enum ContributionKind: String, Hashable, Sendable {
    case iconSet = "Icon set"
    case celebration = "Celebration"
}

/// An entry of a manifest's `iconSets` or `celebrations`.
public protocol AppearanceContribution: Codable, Hashable, Sendable {
    static var kind: ContributionKind { get }
}

/// A manifest's list of one kind of contribution, decoded one entry at a time: a malformed entry
/// becomes a problem the app lists, and the plugin's other contributions, agents and servers still
/// load.
public struct ContributionList<Element: AppearanceContribution>: Hashable, Sendable {
    public var valid: [Element]
    public var malformed: [ContributionProblem]

    public init(_ valid: [Element] = [], malformed: [ContributionProblem] = []) {
        self.valid = valid
        self.malformed = malformed
    }

    public var isEmpty: Bool { valid.isEmpty && malformed.isEmpty }
}

public typealias CelebrationContributions = ContributionList<CelebrationContribution>
public typealias IconSetContributions = ContributionList<IconSetContribution>

extension ContributionList: Codable {
    public init(from decoder: any Decoder) throws {
        self.init()
        guard var container = try? decoder.unkeyedContainer() else {
            malformed = [ContributionProblem(kind: Element.kind, index: nil, id: nil, message: "It should be a list.")]
            return
        }
        while !container.isAtEnd {
            let index = container.currentIndex
            // Entry's decoding never throws, so the container always moves on to the next element.
            switch try container.decode(Entry.self).result {
            case .success(let element): valid.append(element)
            case .failure(let failure):
                malformed.append(
                    ContributionProblem(kind: Element.kind, index: index, id: failure.id, message: failure.message))
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

        let result: Result<Element, Failure>

        private enum IDKey: String, CodingKey {
            case id
        }

        init(from decoder: any Decoder) {
            do {
                result = .success(try Element(from: decoder))
            } catch {
                let id = try? decoder.container(keyedBy: IDKey.self).decode(String.self, forKey: .id)
                let message = ContributionProblem.describe(error, droppingPath: decoder.codingPath.count)
                result = .failure(Failure(id: id, message: message))
            }
        }
    }
}

/// A contribution that couldn't be used, and why, in the user's terms.
public struct ContributionProblem: Hashable, Sendable, CustomStringConvertible {
    public let kind: ContributionKind
    /// Its position in the manifest's list, when the entry couldn't be read at all.
    public let index: Int?
    public let id: String?
    public let message: String
    /// The plugin it came from; set when the catalog collects it.
    public var pluginID: String?

    public init(kind: ContributionKind, index: Int?, id: String?, message: String, pluginID: String? = nil) {
        self.kind = kind
        self.index = index
        self.id = id
        self.message = message
        self.pluginID = pluginID
    }

    /// The id, or "Celebration 3" for an entry without one.
    public var identifier: String {
        id ?? index.map { "\(kind.rawValue) \($0 + 1)" } ?? kind.rawValue
    }

    public var description: String {
        "\(identifier): \(message)"
    }

    /// - Parameter droppingPath: How much of the coding path leads to the entry itself, so paths read
    ///   from the entry ("calendar.start") rather than the manifest.
    public static func describe(_ error: any Error, droppingPath prefix: Int = 0) -> String {
        func path(_ context: DecodingError.Context, _ key: (any CodingKey)? = nil) -> String {
            (context.codingPath.dropFirst(prefix) + [key].compactMap { $0 })
                .map { $0.intValue.map { "[\($0)]" } ?? $0.stringValue }
                .joined(separator: ".")
                .replacingOccurrences(of: ".[", with: "[")
        }
        return switch error {
        case DecodingError.keyNotFound(let key, let context): "Missing \"\(path(context, key))\"."
        case DecodingError.typeMismatch(_, let context), DecodingError.valueNotFound(_, let context):
            "Wrong type at \"\(path(context))\"."
        case DecodingError.dataCorrupted(let context):
            context.codingPath.count <= prefix
                ? context.debugDescription : "\(context.debugDescription) (at \"\(path(context))\")"
        default: error.localizedDescription
        }
    }
}
