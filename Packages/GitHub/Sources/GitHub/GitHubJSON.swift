import Foundation

enum GitHubJSON {
    /// gh prints RFC 3339 dates, with fractional seconds from some endpoints.
    static func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let text = try container.decode(String.self)
            if let date = try? Date(text, strategy: .iso8601) {
                return date
            }
            if let date = try? Date(text, strategy: Date.ISO8601FormatStyle(includingFractionalSeconds: true)) {
                return date
            }
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Not an ISO 8601 date: \(text)")
        }
        return decoder
    }

    static func decode<T: Decodable>(_ type: T.Type, from data: Data) throws(GitHubError) -> T {
        do {
            return try decoder().decode(type, from: data)
        } catch {
            throw .unexpectedOutput(String(describing: error))
        }
    }
}

extension Date {
    /// `nil` for Go's zero time (`0001-01-01T00:00:00Z`), which gh prints for "hasn't happened".
    var ifSet: Date? {
        self > Date(timeIntervalSince1970: 0) ? self : nil
    }
}
