import Foundation

public struct PluginCatalogEntry: Decodable, Hashable, Sendable {
    public let id: String
    public let version: String
    public let repository: URL
    public let commit: String
    public let path: String
    public let archiveURL: URL
    public let sha256: String
    public let size: Int64

    public enum Field: String, CodingKey, Sendable {
        case id, version, repository, commit, path, archiveURL, sha256, size
    }

    public init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: Field.self)
        let id = try values.decode(String.self, forKey: .id)
        self.id = id
        func require(_ condition: Bool, _ field: Field) throws {
            guard condition else { throw PluginCatalogError.invalidEntry(id: id, field: field) }
        }
        func httpsURL(_ field: Field) throws -> URL {
            let raw = try values.decode(String.self, forKey: field)
            guard let url = URL(string: raw, encodingInvalidCharacters: false),
                url.scheme?.lowercased() == "https", let host = url.host, !host.isEmpty,
                url.user == nil, url.password == nil
            else { throw PluginCatalogError.invalidEntry(id: id, field: field) }
            return url
        }
        func matches(_ value: String, _ pattern: String) -> Bool {
            value.range(of: pattern, options: .regularExpression) != nil
        }
        try require(matches(id, #"\A[a-z0-9]+(?:-[a-z0-9]+)*\z"#), .id)
        version = try values.decode(String.self, forKey: .version)
        try require(!version.isEmpty, .version)
        repository = try httpsURL(.repository)
        archiveURL = try httpsURL(.archiveURL)
        commit = try values.decode(String.self, forKey: .commit)
        try require(matches(commit, #"\A[0-9a-f]{40}\z"#), .commit)
        sha256 = try values.decode(String.self, forKey: .sha256)
        try require(matches(sha256, #"\A[0-9a-f]{64}\z"#), .sha256)
        path = try values.decode(String.self, forKey: .path)
        let components = path.split(separator: "/", omittingEmptySubsequences: false)
        try require(
            !path.contains("\\") && !path.contains("\0")
                && components.allSatisfy { !$0.isEmpty && $0 != "." && $0 != ".." }, .path)
        size = try values.decode(Int64.self, forKey: .size)
        try require(size > 0, .size)
    }
}
