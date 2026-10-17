import Foundation

/// An enum gh prints as a string. GitHub adds values over time, so an unknown value becomes
/// `.other` rather than failing the whole response, and gh's empty string for null becomes `nil`.
/// Matching ignores case because `gh search` prints lowercase where GraphQL uses uppercase.
protocol GitHubEnum: RawRepresentable<String> {
    static var other: Self { get }
}

extension GitHubEnum {
    init?(wire: String?) {
        guard let wire, !wire.isEmpty else { return nil }
        self = Self(rawValue: wire) ?? Self(rawValue: wire.uppercased()) ?? Self(rawValue: wire.lowercased()) ?? .other
    }
}

extension KeyedDecodingContainer {
    func decodeEnum<Value: GitHubEnum>(_ type: Value.Type, forKey key: Key) throws -> Value? {
        Value(wire: try decodeIfPresent(String.self, forKey: key))
    }

    /// A string, with gh's empty string for "none" read as `nil`.
    func decodeText(forKey key: Key) throws -> String? {
        try decodeIfPresent(String.self, forKey: key).flatMap { $0.isEmpty ? nil : $0 }
    }
}
