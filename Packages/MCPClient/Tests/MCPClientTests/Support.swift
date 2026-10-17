import Foundation
import MCPClient

/// Fixture files from the test bundle.
enum Fixture {
    static func url(_ name: String) -> URL {
        // `Bundle.module` is only generated for targets with resources, which this one has.
        Bundle.module.url(forResource: "Fixtures/\(name)", withExtension: nil) ?? URL(filePath: "/missing/\(name)")
    }

    static func data(_ name: String) -> Data {
        (try? Data(contentsOf: url(name))) ?? Data()
    }
}

/// A machine whose files are whatever the test says, so configuration paths can be absolute and
/// stable (`/home/tester/.claude.json`, `/work/app/.mcp.json`).
struct FakeFiles: ConfigFileSystem {
    var files: [String: Data]

    init(_ files: [String: String]) {
        self.files = files.mapValues { Fixture.data($0) }
    }

    func contents(atPath path: String) -> Data? {
        files[path]
    }

    func fileExists(atPath path: String) -> Bool {
        files[path] != nil
    }
}

extension URL {
    static let testHome = URL(filePath: "/home/tester", directoryHint: .isDirectory)
    static let app = URL(filePath: "/work/app", directoryHint: .isDirectory)
    static let site = URL(filePath: "/work/site", directoryHint: .isDirectory)
}
