import Foundation
import Testing

@testable import TaskList

@Suite struct FolderHistoryTests {
    @Test func successfulOpensAreNewestFirstAndBounded() throws {
        var history = FolderHistory()
        for number in 0..<8 { history.opened(URL(filePath: "/fixture/\(number)")) }
        #expect(history.entries.count == 6)
        #expect(history.entries.map(\.url.lastPathComponent) == ["7", "6", "5", "4", "3", "2"])
        let bookmark = Data([1, 2, 3])
        history.opened(URL(filePath: "/fixture/4"), bookmark: bookmark)
        #expect(history.entries.first?.url.lastPathComponent == "4")
        #expect(history.entries.first?.bookmark == bookmark)
        #expect(history.entries.count == 6)
        history.opened(URL(filePath: "/fixture/4", directoryHint: .isDirectory), bookmark: bookmark)
        #expect(history.entries.count == 6)
        #expect(history.entries.filter { $0.url.lastPathComponent == "4" }.count == 1)
        let restored = try JSONDecoder().decode(FolderHistory.self, from: JSONEncoder().encode(history))
        #expect(restored == history)
    }

    @Test func remoteURLsNeverEnterLocalHistoryAndClearingIsIndependent() throws {
        var history = FolderHistory()
        history.opened(URL(filePath: "/fixture/atlas"))
        history.opened(try #require(URL(string: "https://example.invalid/atlas")))
        #expect(history.entries.count == 1)
        history.clear()
        #expect(history.entries.isEmpty)
    }
}
