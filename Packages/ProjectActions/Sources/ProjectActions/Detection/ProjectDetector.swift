import Foundation

/// Finds the actions a project offers from the files at its root: package.json scripts (with the
/// package manager its lockfile names), justfile recipes, Makefile targets, Cargo, SwiftPM and
/// Xcode, Go, Python (uv, Poetry, pip, pytest), Gradle, Maven and Compose files.
///
/// It reads the file system synchronously and costs a directory listing and a few small files, so
/// run it off the main thread.
public enum ProjectDetector {
    public static func suggestions(in root: URL) -> [ProjectSuggestion] {
        let folder = ProjectFolder(root)
        return detectors.flatMap { $0(folder) }
    }

    private static let detectors: [@Sendable (ProjectFolder) -> [ProjectSuggestion]] = [
        JustfileDetector.detect,
        MakefileDetector.detect,
        PackageJSONDetector.detect,
        CargoDetector.detect,
        SwiftDetector.detect,
        GoDetector.detect,
        PythonDetector.detect,
        JVMDetector.detect,
        ComposeDetector.detect,
    ]
}

extension ProjectSuggestion {
    /// A suggestion for a script, recipe or target the project names itself. It keeps the
    /// project's name, capitalized; a well-known name ("fmt") gets its role's place and icon.
    static func named(_ name: String, command: String, source: Source, detail: String? = nil) -> Self {
        let role = Role.of(name) ?? .other
        return Self(
            name: name.prefix(1).uppercased() + name.dropFirst(), command: command, role: role, source: source,
            detail: detail, presentation: role == .format ? .background : .terminal)
    }
}
