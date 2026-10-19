import Foundation

extension GitHubCLI {
    /// How many branches one GraphQL request asks about.
    static let mergedPullRequestBatch = 50

    /// The merged pull requests of local branches in the repository at `directory`, keyed by
    /// branch; branches without one are left out. Each branch is looked up by its head name, and
    /// by the pull request a task was opened for when it has one, in one GraphQL request per 50
    /// branches plus one `gh repo view`. Read-only.
    public func mergedPullRequests(
        for queries: [MergedPullRequest.Query], in directory: URL
    ) async throws(GitHubError) -> [String: [MergedPullRequest]] {
        guard !queries.isEmpty else { return [:] }
        let owner = try await repository(.directory(directory)).nameWithOwner.split(separator: "/", maxSplits: 1)
        guard owner.count == 2 else { throw .unexpectedOutput("repo view: \(owner.joined(separator: "/"))") }
        var found: [String: [MergedPullRequest]] = [:]
        for start in stride(from: 0, to: queries.count, by: Self.mergedPullRequestBatch) {
            let batch = Array(queries[start..<min(start + Self.mergedPullRequestBatch, queries.count)])
            let command = GitHubCommand.mergedPullRequests(
                batch, owner: String(owner[0]), name: String(owner[1]), in: directory)
            let response = try GitHubJSON.decode(MergedPullRequestResponse.self, from: try await run(command))
            for (index, query) in batch.enumerated() {
                var pullRequests = response.data.byHead["h\(index)"] ?? []
                if let linked = response.data.byLink["u\(index)"], !pullRequests.contains(linked) {
                    pullRequests.append(linked)
                }
                if !pullRequests.isEmpty { found[query.branch] = pullRequests }
            }
        }
        return found
    }
}

extension GitHubCommand {
    /// One GraphQL request for a batch of `GitHubCLI.mergedPullRequests`: an aliased
    /// `pullRequests(headRefName:)` per branch (`h0`, `h1`…) and a `resource(url:)` per linked pull
    /// request (`u0`…). Branch names and links go in as variables, never into the query text.
    public static func mergedPullRequests(
        _ queries: [MergedPullRequest.Query], owner: String, name: String, in directory: URL
    ) -> GitHubCommand {
        var declarations = ["$owner: String!", "$name: String!"]
        var heads: [String] = []
        var links: [String] = []
        var variables: [String: GraphQLRequest.Value] = ["owner": .string(owner), "name": .string(name)]
        for (index, query) in queries.enumerated() {
            declarations.append("$h\(index): String!")
            variables["h\(index)"] = .string(query.head)
            heads.append(
                "h\(index): pullRequests(headRefName: $h\(index), states: MERGED, first: 5, "
                    + "orderBy: {field: UPDATED_AT, direction: DESC}) { nodes { ...merged } }")
            if let link = query.pullRequest {
                declarations.append("$u\(index): URI!")
                variables["u\(index)"] = .string(link.absoluteString)
                links.append("u\(index): resource(url: $u\(index)) { ... on PullRequest { state ...merged } }")
            }
        }
        let query = """
            query MergedCleanup(\(declarations.joined(separator: ", "))) {
              repository(owner: $owner, name: $name) {
                \(heads.joined(separator: "\n    "))
              }
              \(links.joined(separator: "\n  "))
            }
            fragment merged on PullRequest { number url headRefName headRefOid baseRefName mergedAt }
            """
        return GitHubCommand(
            ["api", "graphql", "--input", "-"], in: .directory(directory),
            input: GraphQLRequest(query: query, variables: variables).data)
    }
}

/// `GitHubCommand.mergedPullRequests`' answer: `data.repository.h<n>.nodes` and `data.u<n>`.
struct MergedPullRequestResponse: Decodable {
    let data: Payload

    struct Payload: Decodable {
        var byHead: [String: [MergedPullRequest]] = [:]
        var byLink: [String: MergedPullRequest] = [:]

        init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: AliasKey.self)
            for key in container.allKeys {
                if key.stringValue == "repository" {
                    let repository = try container.decodeIfPresent([String: Connection?].self, forKey: key) ?? [:]
                    byHead = repository.compactMapValues { $0?.nodes }
                } else if let node = try container.decodeIfPresent(LinkedNode.self, forKey: key),
                    node.state == "MERGED", let pullRequest = node.pullRequest
                {
                    byLink[key.stringValue] = pullRequest
                }
            }
        }
    }

    struct Connection: Decodable {
        let nodes: [MergedPullRequest]
    }

    /// A linked pull request in any state, or `{}` when the link wasn't to a pull request.
    struct LinkedNode: Decodable {
        let state: String?
        let pullRequest: MergedPullRequest?

        init(from decoder: any Decoder) throws {
            state = try decoder.container(keyedBy: AliasKey.self).decodeIfPresent(
                String.self, forKey: AliasKey(stringValue: "state"))
            pullRequest = try? MergedPullRequest(from: decoder)
        }
    }

    struct AliasKey: CodingKey {
        let stringValue: String
        var intValue: Int? { nil }

        init(stringValue: String) {
            self.stringValue = stringValue
        }

        init?(intValue: Int) {
            nil
        }
    }
}
