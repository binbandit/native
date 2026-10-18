import Foundation

/// `{"data": …}`, GraphQL's response envelope. Errors make gh exit unsuccessfully, so a decoded
/// response has its data.
struct GraphQLResponse<Payload: Decodable>: Decodable {
    var data: Payload
}

/// `{ nodes: [...] }`.
struct Nodes<Node: Decodable>: Decodable {
    var nodes: [Node]

    private enum CodingKeys: String, CodingKey {
        case nodes
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        // Nodes GitHub can't resolve (deleted accounts, inaccessible items) come back null.
        nodes = (try container.decodeIfPresent([Node?].self, forKey: .nodes) ?? []).compactMap(\.self)
    }
}

/// A connection page: its nodes, the total, and where the next page starts.
struct Page<Node: Decodable>: Decodable {
    struct PageInfo: Decodable {
        var hasNextPage: Bool?
        var endCursor: String?

        var next: String? {
            hasNextPage == true ? endCursor : nil
        }
    }

    var nodes: [Node]
    var totalCount: Int
    var pageInfo: PageInfo

    private enum CodingKeys: String, CodingKey {
        case nodes, totalCount, pageInfo
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        nodes = (try container.decodeIfPresent([Node?].self, forKey: .nodes) ?? []).compactMap(\.self)
        totalCount = try container.decodeIfPresent(Int.self, forKey: .totalCount) ?? nodes.count
        pageInfo = try container.decodeIfPresent(PageInfo.self, forKey: .pageInfo) ?? PageInfo()
    }
}
