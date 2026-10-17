import Foundation
@testable import GitHub

/// JSON captured from `gh` on a real account (read-only commands), in `Fixtures/`.
enum Fixtures {
    static var directory: URL {
        get throws {
            guard let url = Bundle.module.url(forResource: "Fixtures", withExtension: nil) else {
                throw CocoaError(.fileNoSuchFile)
            }
            return url
        }
    }

    static func data(_ name: String) throws -> Data {
        try Data(contentsOf: directory.appending(path: "\(name).json"))
    }

    static func decode<T: Decodable>(_ type: T.Type, from name: String) throws -> T {
        try GitHubJSON.decode(type, from: data(name))
    }
}
