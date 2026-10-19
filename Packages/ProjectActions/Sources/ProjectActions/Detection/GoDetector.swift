import Foundation

/// go.mod: test and build every package, and run the root's main package.
enum GoDetector {
    static func detect(_ folder: ProjectFolder) -> [ProjectSuggestion] {
        guard folder.has("go.mod") else { return [] }
        var suggestions = [
            ProjectSuggestion(name: "Test", command: "go test ./...", role: .test, source: .go),
            ProjectSuggestion(name: "Build", command: "go build ./...", role: .build, source: .go),
        ]
        let hasMain = folder.entries.sorted().contains { name in
            name.hasSuffix(".go") && !name.hasSuffix("_test.go")
                && folder.text(name)?.contains("package main") == true
        }
        if hasMain {
            suggestions.append(ProjectSuggestion(name: "Run", command: "go run .", role: .run, source: .go))
        }
        return suggestions
    }
}
