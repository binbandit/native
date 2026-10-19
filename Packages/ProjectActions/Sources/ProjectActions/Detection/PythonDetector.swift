import Foundation

/// A Python project: installing with the tool it uses (uv, Poetry or pip), and pytest when the
/// project uses it, run through that tool.
enum PythonDetector {
    static func detect(_ folder: ProjectFolder) -> [ProjectSuggestion] {
        let pyproject = folder.has("pyproject.toml") ? folder.text("pyproject.toml") ?? "" : nil
        let requirements = folder.has("requirements.txt") ? folder.text("requirements.txt") ?? "" : nil
        guard pyproject != nil || requirements != nil || folder.has("setup.py") else { return [] }

        let tool = Tool.used(by: folder, pyproject: pyproject ?? "")
        var suggestions: [ProjectSuggestion] = []
        if let install = tool.install(hasRequirements: requirements != nil, hasProject: pyproject != nil) {
            suggestions.append(
                ProjectSuggestion(name: "Install", command: install, role: .install, source: .python))
        }
        let usesPytest =
            folder.has("pytest.ini") || folder.has("conftest.py")
            || pyproject?.contains("pytest") == true || requirements?.contains("pytest") == true
            || folder.first(of: ["requirements-dev.txt", "dev-requirements.txt"]).flatMap(folder.text)?
                .contains("pytest") == true
            || folder.isDirectory("tests")
        if usesPytest {
            suggestions.append(
                ProjectSuggestion(name: "Test", command: tool.running("pytest"), role: .test, source: .python))
        }
        return suggestions
    }

    enum Tool {
        case uv, poetry, pip

        static func used(by folder: ProjectFolder, pyproject: String) -> Self {
            if folder.has("uv.lock") || pyproject.contains("[tool.uv") { return .uv }
            if folder.has("poetry.lock") || pyproject.contains("[tool.poetry") { return .poetry }
            return .pip
        }

        func install(hasRequirements: Bool, hasProject: Bool) -> String? {
            switch self {
            case .uv: "uv sync"
            case .poetry: "poetry install"
            case .pip:
                hasRequirements
                    ? "python3 -m pip install -r requirements.txt"
                    : hasProject ? "python3 -m pip install -e ." : nil
            }
        }

        func running(_ program: String) -> String {
            switch self {
            case .uv: "uv run \(program)"
            case .poetry: "poetry run \(program)"
            case .pip: "python3 -m \(program)"
            }
        }
    }
}
