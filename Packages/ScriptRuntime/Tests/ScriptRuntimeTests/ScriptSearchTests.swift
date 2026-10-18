import Testing

@testable import ScriptRuntime

@Suite struct ScriptSearchTests {
    let bindings = [
        ScriptBinding(path: ["rea", "list_procedures"], summary: "Lists every analyzed procedure.") { _ in nil },
        ScriptBinding(path: ["rea", "search_strings"], summary: "Searches strings for a procedure name.") { _ in nil },
        ScriptBinding(path: ["github", "list_issues"], summary: "Lists a repository's issues.") { _ in nil },
    ]

    @Test func labelMatchesRankFirstAndEveryWordMustMatch() {
        let found = ScriptReference.search(bindings, query: "Procedure", limit: 10).map(\.label)
        #expect(found == ["tools.rea.list_procedures", "tools.rea.search_strings"])
        #expect(ScriptReference.search(bindings, query: "list issues", limit: 10).map(\.label) == ["tools.github.list_issues"])
        #expect(ScriptReference.search(bindings, query: "list nothing", limit: 10).isEmpty)
    }

    @Test func emptyQueryListsEverythingUpToTheLimit() {
        #expect(
            ScriptReference.search(bindings, query: "", limit: 2).map(\.label) == [
                "tools.github.list_issues", "tools.rea.list_procedures",
            ])
    }
}
