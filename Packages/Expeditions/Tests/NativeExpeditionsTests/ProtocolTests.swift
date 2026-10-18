import Foundation
import Testing

@testable import NativeExpeditions

@Suite struct RouteParserTests {
    @Test func readsAFencedRouteWithProseAndFillsGaps() throws {
        let reply = """
            I looked around. Here's the route:

            <route>
            ```json
            {"legs": [{"title": "Core", "assignments": [
              {"title": "Add the CSV writer!", "brief": "Do it."},
              {"title": "Add the CSV writer!", "assignee": "nobody", "after": ["add-the-csv-writer"]}
            ]}]}
            ```
            </route>
            Let me know.
            """
        let route = try RouteParser.parse(reply, builders: ["codex", "claude-code"]).get()
        let assignments = route.legs[0].assignments
        #expect(assignments.map(\.id) == ["add-the-csv-writer", "add-the-csv-writer-2"])
        #expect(assignments.map(\.assignee) == ["codex", "claude-code"])
        #expect(assignments[1].brief == "Add the CSV writer!")
        #expect(assignments[0].doneWhen == ["Core"])
        #expect(route.legs[0].id == "leg-1")
    }

    @Test func rejectsWhatTheEngineCantRun() {
        func problem(_ json: String) -> String? {
            if case .failure(let problem) = RouteParser.parse("<route>\(json)</route>", builders: ["codex"]) {
                return problem.message
            }
            return nil
        }
        #expect(problem(#"{"legs": []}"#)?.contains("no assignments") == true)
        #expect(
            problem(#"{"legs": [{"assignments": [{"title": "A", "after": ["z"]}]}]}"#)?.contains("isn't an assignment")
                == true)
        #expect(
            problem(
                #"{"legs": [{"assignments": [{"id": "a", "title": "A", "after": ["b"]}, {"id": "b", "title": "B", "after": ["a"]}]}]}"#
            )?.contains("wait for each other") == true)
        #expect(
            problem(#"{"legs": [{"assignments": [{"id": "a", "title": "A"}, {"id": "a", "title": "B"}]}]}"#)?.contains(
                "Two assignments") == true)
        #expect(problem(#"{"legs": [{"assignments": [{"brief": "x"}]}]}"#)?.contains("has no title") == true)
        #expect(problem(#"{"legs": "many"}"#)?.contains("isn't valid JSON") == true)
        if case .failure(let missing) = RouteParser.parse("no block here", builders: []) {
            #expect(missing.message.contains("has no <route> block"))
        }
    }

    @Test func laterLegsMayComeAfterEarlierOnes() throws {
        let json =
            #"{"legs": [{"assignments": [{"id": "a", "title": "A"}]}, {"assignments": [{"id": "b", "title": "B", "after": ["a"]}]}]}"#
        let route = try RouteParser.parse("<route>\(json)</route>", builders: ["codex"]).get()
        #expect(route.legs.map(\.id) == ["leg-1", "leg-2"])
        let revision = try RouteParser.parse(
            #"<route>{"legs": [{"assignments": [{"id": "c", "title": "C", "after": ["a"]}]}]}</route>"#,
            builders: ["codex"], earlier: ["a"]
        ).get()
        #expect(revision.assignments.map(\.after) == [["a"]])
    }
}

@Suite struct CheckpointVerdictTests {
    @Test func readsDecoratedVerdictLines() throws {
        let pass = try #require(CheckpointVerdict(parsing: "All good.\n**VERDICT: pass** - ran the tests"))
        #expect(pass.outcome == .pass)
        #expect(pass.note == "ran the tests")
        #expect(pass.findings == "All good.")

        let changes = try #require(
            CheckpointVerdict(parsing: "1. Broken quoting\n\n`Verdict: changes - Quoting is broken`\nThanks!"))
        #expect(changes.outcome == .changes)
        #expect(changes.note == "Quoting is broken")
        #expect(changes.findings == "1. Broken quoting\n\nThanks!")

        #expect(CheckpointVerdict(parsing: "VERDICT: passed")?.outcome == .pass)
        #expect(CheckpointVerdict(parsing: "VERDICT: failed - nope")?.outcome == .changes)
    }

    @Test func ignoresVerdictsThatArentReports() {
        #expect(CheckpointVerdict(parsing: "No verdict here.") == nil)
        #expect(CheckpointVerdict(parsing: "VERDICT: passable work overall") == nil)
        let buried = "VERDICT: pass\n" + (1...8).map { "line \($0)" }.joined(separator: "\n")
        #expect(CheckpointVerdict(parsing: buried) == nil)
    }
}

@Suite struct ExpeditionArtifactTests {
    @Test @MainActor func writesProtectedFilesAndPutsBackChangedOnes() throws {
        var driver = ExpeditionDriver()
        driver.setOut()
        driver.end(.assignment("writer"), "Wrote it.\nGOAL: complete - tests pass")
        let root = FileManager.default.temporaryDirectory.appending(path: "expedition-docs-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let documents = ExpeditionDocuments(root: root)
        #expect(documents.write(driver.expedition).isEmpty)

        let folder = documents.folder(for: driver.expedition.id)
        let route = folder.appending(path: "route.md")
        let text = try String(contentsOf: route, encoding: .utf8)
        #expect(text.contains("### Add the CSV writer"))
        #expect(
            try String(contentsOf: folder.appending(path: "reports/writer.md"), encoding: .utf8).contains("Wrote it."))
        let permissions = try FileManager.default.attributesOfItem(atPath: route.path)[.posixPermissions] as? Int
        #expect(permissions == 0o444)

        // An agent loosening the route gets it put back.
        try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: route.path)
        try Data("# Done already".utf8).write(to: route)
        #expect(documents.write(driver.expedition) == ["route.md"])
        #expect(try String(contentsOf: route, encoding: .utf8) == text)
    }

    @Test func readinessWarnsWithTheFixAndBlocksOnlyWithoutACrew() {
        var readiness = ExpeditionReadiness()
        #expect(!readiness.canStart)
        readiness.crew = Crew(
            lead: ExpeditionDriver.claude, builders: [ExpeditionDriver.claude], reviewer: ExpeditionDriver.claude)
        readiness.isRepository = false
        readiness.gitHubReady = false
        #expect(readiness.canStart)
        let ids = readiness.warnings.map(\.id)
        #expect(ids == ["git", "reviewer", "budget", "github", "pull-request"])
    }

    @Test func suggestedCrewMixesProviders() throws {
        let crew = try #require(
            Crew.suggested(from: [ExpeditionDriver.claude, ExpeditionDriver.codex], preferring: "codex"))
        #expect(crew.lead == ExpeditionDriver.codex)
        #expect(crew.reviewer == ExpeditionDriver.claude)
        #expect(crew.builders == [ExpeditionDriver.codex, ExpeditionDriver.claude])
    }
}
