import Foundation

/// A Swift package (`swift build`, `swift test`) or an Xcode project or workspace: an
/// `xcodebuild` build per shared scheme, and a test for schemes that have tests.
enum SwiftDetector {
    static func detect(_ folder: ProjectFolder) -> [ProjectSuggestion] {
        swiftPackage(folder) + xcode(folder)
    }

    private static func swiftPackage(_ folder: ProjectFolder) -> [ProjectSuggestion] {
        guard folder.has("Package.swift") else { return [] }
        var suggestions = [
            ProjectSuggestion(name: "Build", command: "swift build", role: .build, source: .swiftPackage)
        ]
        if folder.isDirectory("Tests") {
            suggestions.append(
                ProjectSuggestion(name: "Test", command: "swift test", role: .test, source: .swiftPackage))
        }
        return suggestions
    }

    /// At most this many schemes each get a build and a test; a project with dozens has the rest
    /// one edit away.
    private static let maxSchemes = 3

    private static func xcode(_ folder: ProjectFolder) -> [ProjectSuggestion] {
        // A workspace holds the project and its packages or pods, so it's what builds.
        let container =
            folder.entries.sorted().first { $0.hasSuffix(".xcworkspace") }
            ?? folder.entries.sorted().first { $0.hasSuffix(".xcodeproj") }
        guard let container else { return [] }
        let flag = container.hasSuffix(".xcworkspace") ? "-workspace" : "-project"
        let schemes = sharedSchemes(in: folder, container: container)
        var suggestions: [ProjectSuggestion] = []
        for scheme in schemes.prefix(maxSchemes) {
            let base = "xcodebuild \(flag) \(Self.quoted(container)) -scheme \(Self.quoted(scheme.name))"
            let suffix = schemes.count > 1 ? " \(scheme.name)" : ""
            suggestions.append(
                ProjectSuggestion(name: "Build\(suffix)", command: "\(base) build", role: .build, source: .xcode))
            if scheme.hasTests {
                suggestions.append(
                    ProjectSuggestion(name: "Test\(suffix)", command: "\(base) test", role: .test, source: .xcode))
            }
        }
        return suggestions
    }

    struct Scheme: Equatable {
        let name: String
        let hasTests: Bool
    }

    /// The schemes checked in with the project (`xcshareddata/xcschemes`), which are the ones a
    /// team shares; a workspace's own and its first project's both count.
    static func sharedSchemes(in folder: ProjectFolder, container: String) -> [Scheme] {
        var places = ["\(container)/xcshareddata/xcschemes"]
        if container.hasSuffix(".xcworkspace"),
            let project = folder.entries.sorted().first(where: { $0.hasSuffix(".xcodeproj") })
        {
            places.append("\(project)/xcshareddata/xcschemes")
        }
        var seen: Set<String> = []
        return places.flatMap { place in
            folder.entries(in: place).filter { $0.hasSuffix(".xcscheme") }.compactMap { file -> Scheme? in
                let name = String(file.dropLast(".xcscheme".count))
                guard seen.insert(name).inserted else { return nil }
                let hasTests = folder.text("\(place)/\(file)")?.contains("<TestableReference") ?? false
                return Scheme(name: name, hasTests: hasTests)
            }
        }
    }

    private static func quoted(_ text: String) -> String {
        text.contains(where: { $0.isWhitespace || "'\"$&;()|<>*?".contains($0) })
            ? "'\(text.replacingOccurrences(of: "'", with: "'\\''"))'" : text
    }
}
