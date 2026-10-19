import Foundation

/// Gradle and Maven: build and test, through the project's wrapper script when it has one.
enum JVMDetector {
    static func detect(_ folder: ProjectFolder) -> [ProjectSuggestion] {
        gradle(folder) + maven(folder)
    }

    private static func gradle(_ folder: ProjectFolder) -> [ProjectSuggestion] {
        let files = ["build.gradle", "build.gradle.kts", "settings.gradle", "settings.gradle.kts"]
        guard folder.has("gradlew") || folder.first(of: files) != nil else { return [] }
        let gradle = folder.has("gradlew") ? "./gradlew" : "gradle"
        return [
            ProjectSuggestion(name: "Test", command: "\(gradle) test", role: .test, source: .gradle),
            ProjectSuggestion(name: "Build", command: "\(gradle) build", role: .build, source: .gradle),
        ]
    }

    private static func maven(_ folder: ProjectFolder) -> [ProjectSuggestion] {
        guard folder.has("pom.xml") else { return [] }
        let maven = folder.has("mvnw") ? "./mvnw" : "mvn"
        return [
            ProjectSuggestion(name: "Test", command: "\(maven) test", role: .test, source: .maven),
            ProjectSuggestion(name: "Package", command: "\(maven) package", role: .build, source: .maven),
        ]
    }
}
