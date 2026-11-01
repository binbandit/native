import Foundation
import Testing

@testable import SessionTitling

@Suite("Title evaluation", .serialized)
struct TitleEvaluationTests {
    struct Fixture: Codable {
        var id: Int
        var project: String
        var message: String
        var outcome: String
        var ideal: String
        var keywords: [String]
        var before: String
        var initial: String
        var refined: String
        var after: String
    }

    static func fixtures() throws -> [Fixture] {
        let url = try #require(Bundle.module.url(forResource: "tasks", withExtension: "json", subdirectory: "Fixtures"))
        return try JSONDecoder().decode([Fixture].self, from: Data(contentsOf: url))
    }

    /// Six independent points, using subject keywords written before model capture. This checks
    /// recognition and format; reviewers still compare the full table for semantic mistakes.
    static func score(_ title: String, fixture: Fixture) -> [Int] {
        let lower = title.lowercased()
        let source = fixture.message + "\n" + fixture.outcome
        return [
            fixture.keywords.contains { lower.contains($0.lowercased()) },
            (2...6).contains(title.split(whereSeparator: \.isWhitespace).count),
            SessionTitleRules.sentenceCase(title, keeping: source) == title,
            !SessionTitleRules.filler.contains { lower.hasPrefix($0) },
            !title.contains("\"") && title.last.map { !".,:;!?…".contains($0) } == true,
            SessionTitleInput.isSafeTitle(title),
        ].map { $0 ? 1 : 0 }
    }

    @Test("Forty offline replays improve recognition and format over captured baseline titles")
    func evaluation() throws {
        let fixtures = try Self.fixtures()
        #expect(fixtures.count == 40)
        var before = Array(repeating: 0, count: 6)
        var after = Array(repeating: 0, count: 6)
        for fixture in fixtures {
            var state = SessionTitleState()
            state.begin(SessionTitleRequest(projectName: fixture.project, prompt: fixture.message))
            if !fixture.initial.isEmpty { state.accept(generated: fixture.initial) }
            state.finishFirstTurn(outcome: fixture.outcome)
            if state.refinementCount == 1, !fixture.refined.isEmpty {
                state.accept(generated: fixture.refined, revision: 1)
            }
            let actual = state.generated ?? state.fallback ?? ""
            #expect(actual == fixture.after, "Fixture \(fixture.id)")
            let oldScore = Self.score(fixture.before, fixture: fixture)
            let newScore = Self.score(actual, fixture: fixture)
            for index in before.indices {
                before[index] += oldScore[index]
                after[index] += newScore[index]
            }
        }
        #expect(after[0] >= before[0])
        #expect(after[1] >= before[1] + 8)
        #expect(after[3...] == [40, 40, 40])
        #expect(after.reduce(0, +) >= before.reduce(0, +) + 12)
        print("Title evaluation (specific, short, case, filler, punctuation, privacy): \(before) -> \(after)")
    }

    @Test(
        "Capture actual on-device titles for synthetic fixtures",
        .enabled(if: ProcessInfo.processInfo.environment["TITLE_CAPTURE"] != nil))
    func capture() async throws {
        let destination = try #require(ProcessInfo.processInfo.environment["TITLE_CAPTURE"])
        var results: [[String: String]] = []
        let selected = ProcessInfo.processInfo.environment["TITLE_CAPTURE_IDS"]?.split(separator: ",").compactMap {
            Int($0)
        }
        for fixture in try Self.fixtures() where selected == nil || selected?.contains(fixture.id) == true {
            let request = SessionTitleRequest(projectName: fixture.project, prompt: fixture.message)
            let title: String?
            do { title = try await OnDeviceTitleGenerator().title(for: request) } catch { title = nil }
            var state = SessionTitleState()
            state.begin(request)
            if let title { state.accept(generated: title) }
            state.finishFirstTurn(outcome: fixture.outcome)
            var refined: String?
            if state.refinementCount == 1, let pending = state.request {
                do { refined = try await OnDeviceTitleGenerator().title(for: pending) } catch { refined = nil }
                if let refined { state.accept(generated: refined, revision: 1) }
            }
            results.append([
                "id": String(fixture.id), "title": title ?? "", "refined": refined ?? "",
                "final": state.generated ?? state.fallback ?? "",
                "fallback": SessionTitleRules.fallback(from: fixture.message) ?? "",
            ])
            try JSONSerialization.data(withJSONObject: results, options: [.prettyPrinted, .sortedKeys]).write(
                to: URL(filePath: destination))
            print("Captured fixture \(fixture.id): \(title ?? "model unavailable")")
        }
    }
}
