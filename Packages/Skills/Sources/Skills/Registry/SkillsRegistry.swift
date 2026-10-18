import Foundation

/// GET requests, so the registry can be reached from whichever machine has the network, and
/// tests can answer with captured responses.
public protocol SkillsHTTPClient: Sendable {
    /// The body and status code of a GET.
    func get(_ url: URL) async throws -> (Data, Int)
}

public struct URLSessionSkillsHTTP: SkillsHTTPClient {
    public init() {}

    public func get(_ url: URL) async throws -> (Data, Int) {
        var request = URLRequest(url: url, timeoutInterval: 20)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, response) = try await URLSession.shared.data(for: request)
        return (data, (response as? HTTPURLResponse)?.statusCode ?? 0)
    }
}

/// skills.sh, the open registry the `skills` CLI (`npx skills`) searches and installs from. It
/// indexes skills in public GitHub repositories and serves each skill's files, so Native can show
/// every file before writing any.
public struct SkillsRegistry: Sendable {
    public static let skillsSH = URL(string: "https://skills.sh") ?? URL(filePath: "/")

    let base: URL
    let http: any SkillsHTTPClient

    public init(base: URL = SkillsRegistry.skillsSH, http: any SkillsHTTPClient = URLSessionSkillsHTTP()) {
        self.base = base
        self.http = http
    }

    /// The most-installed skills matching `query`.
    public func search(_ query: String, limit: Int = 20) async throws(SkillsRegistryError) -> [RegistrySkill] {
        var components = URLComponents(url: base.appending(path: "api/search"), resolvingAgainstBaseURL: false)
        components?.queryItems = [
            URLQueryItem(name: "q", value: query), URLQueryItem(name: "limit", value: "\(limit)"),
        ]
        guard let url = components?.url else { throw .badResponse }
        let response: SearchResponse = try await get(url)
        return response.skills.sorted { ($0.installs ?? 0) > ($1.installs ?? 0) }
    }

    /// A skill's files, by path inside its folder.
    public func files(of skill: RegistrySkill) async throws(SkillsRegistryError) -> [RegistryFile] {
        try await files(source: skill.source, skill: skill.skillId)
    }

    public func files(source: String, skill: String) async throws(SkillsRegistryError) -> [RegistryFile] {
        let parts = source.split(separator: "/").map(String.init)
        guard parts.count == 2 else { throw .badResponse }
        let url = base.appending(path: "api/download").appending(path: parts[0]).appending(path: parts[1])
            .appending(path: skill)
        let response: DownloadResponse = try await get(url)
        return response.files
    }

    private func get<Response: Decodable>(_ url: URL) async throws(SkillsRegistryError) -> Response {
        let data: Data
        let status: Int
        do {
            (data, status) = try await http.get(url)
        } catch let error as URLError
            where [.notConnectedToInternet, .networkConnectionLost, .cannotFindHost, .timedOut, .dataNotAllowed]
            .contains(error.code)
        {
            throw .offline
        } catch {
            throw .failed(error.localizedDescription)
        }
        guard status != 404 else { throw .notFound }
        guard (200..<300).contains(status) else { throw .failed("skills.sh answered with status \(status).") }
        do {
            return try JSONDecoder().decode(Response.self, from: data)
        } catch {
            throw .badResponse
        }
    }

    private struct SearchResponse: Decodable {
        var skills: [RegistrySkill]
    }

    private struct DownloadResponse: Decodable {
        var files: [RegistryFile]
    }
}

/// A skill as the registry lists it.
public struct RegistrySkill: Hashable, Sendable, Decodable, Identifiable {
    /// `owner/repo/skill`.
    public var id: String
    /// The GitHub repository, `owner/repo`.
    public var source: String
    public var skillId: String
    public var name: String
    public var installs: Int?

    public init(id: String, source: String, skillId: String, name: String, installs: Int?) {
        self.id = id
        self.source = source
        self.skillId = skillId
        self.name = name
        self.installs = installs
    }

    public var installSource: SkillInstallSource {
        .registry(source: source, skill: skillId)
    }
}

/// One file of a registry skill, as text.
public struct RegistryFile: Hashable, Sendable, Decodable {
    public var path: String
    public var contents: String
}

public enum SkillsRegistryError: Error, Hashable, Sendable, LocalizedError {
    case offline
    case notFound
    case badResponse
    case failed(String)

    public var errorDescription: String? {
        switch self {
        case .offline: "You're offline, so skills.sh can't be reached. Search again when you're connected."
        case .notFound: "skills.sh doesn't have that skill."
        case .badResponse: "skills.sh sent something Native didn't understand."
        case .failed(let reason): reason
        }
    }
}
