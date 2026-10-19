import Foundation

/// Cargo.toml: build, test and clippy, and run when the package has a binary.
enum CargoDetector {
    static func detect(_ folder: ProjectFolder) -> [ProjectSuggestion] {
        guard folder.has("Cargo.toml"), let manifest = folder.text("Cargo.toml") else { return [] }
        var suggestions = [
            ProjectSuggestion(name: "Test", command: "cargo test", role: .test, source: .cargo),
            ProjectSuggestion(name: "Build", command: "cargo build", role: .build, source: .cargo),
            ProjectSuggestion(
                name: "Clippy", command: "cargo clippy", role: .lint, source: .cargo, icon: "wand.and.stars"),
        ]
        // A workspace root with no package of its own has nothing for a bare `cargo run` to run.
        let hasPackage = manifest.contains("[package]")
        let hasBinary = manifest.contains("[[bin]]") || folder.data("src/main.rs") != nil
        if hasPackage && hasBinary {
            suggestions.append(ProjectSuggestion(name: "Run", command: "cargo run", role: .run, source: .cargo))
        }
        return suggestions
    }
}
