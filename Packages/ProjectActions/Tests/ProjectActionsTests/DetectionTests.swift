import Foundation
import Testing

@testable import ProjectActions

/// Each ecosystem against a small fixture repo in `Fixtures/`.
struct DetectionTests {
    private func suggestions(_ fixture: String) throws -> [ProjectSuggestion] {
        let url = try #require(Bundle.module.url(forResource: "Fixtures/\(fixture)", withExtension: nil))
        return ProjectDetector.suggestions(in: url)
    }

    private func commands(_ fixture: String) throws -> [String] {
        try suggestions(fixture).map(\.command)
    }

    @Test func bunRunsScriptsWithBunRun() throws {
        let found = try suggestions("node-bun")
        // `bun test` is Bun's own runner, so the script runs as `bun run test`.
        #expect(
            Set(found.map(\.command)) == [
                "bun install", "bun run build", "bun run db:migrate", "bun run dev", "bun run lint", "bun run test",
            ])
        let test = try #require(found.first { $0.command == "bun run test" })
        #expect(test.name == "Test" && test.role == .test && test.detail == "vitest run")
        #expect(found.first { $0.command == "bun run db:migrate" }?.role == .other)
    }

    @Test func pnpmAndYarnUseTheirLockfiles() throws {
        #expect(try commands("node-pnpm") == ["pnpm install", "pnpm run dev", "pnpm test"])
        #expect(try commands("node-yarn") == ["yarn install", "yarn run start", "yarn test"])
    }

    @Test func npmSkipsThePlaceholderTestScript() throws {
        let found = try suggestions("node-npm")
        #expect(found.map(\.command) == ["npm install", "npm run format", "npm start"])
        // Formatting runs quietly, with a toast.
        #expect(found.first { $0.role == .format }?.presentation == .background)
    }

    @Test func declaredPackageManagerWinsOverTheLockfile() throws {
        #expect(try commands("node-declared") == ["pnpm install", "pnpm run build"])
    }

    @Test func justfileRecipesThatRunWithoutArguments() throws {
        let found = try suggestions("just")
        #expect(found.map(\.command) == ["just test", "just dev", "just lint", "just release", "just build"])
        #expect(found.first?.detail == "Run every test")
        #expect(found.first { $0.command == "just dev" }?.detail == "Start the dev server")
    }

    @Test func makefileNamedTargetsOnly() throws {
        let found = try suggestions("make")
        #expect(found.map(\.command) == ["make all", "make build", "make test", "make clean"])
        #expect(found.first?.detail == "Build and test")
    }

    @Test func cargoRunsOnlyWithABinary() throws {
        #expect(try commands("cargo") == ["cargo test", "cargo build", "cargo clippy", "cargo run"])
        #expect(try commands("cargo-workspace") == ["cargo test", "cargo build", "cargo clippy"])
    }

    @Test func swiftPackageAndXcodeSchemes() throws {
        #expect(try commands("swiftpm") == ["swift build", "swift test"])
        let xcode = try suggestions("xcode")
        #expect(
            xcode.map(\.command) == [
                "xcodebuild -project App.xcodeproj -scheme App build",
                "xcodebuild -project App.xcodeproj -scheme App test",
                "xcodebuild -project App.xcodeproj -scheme Widget build",
            ])
        #expect(xcode.map(\.name) == ["Build App", "Test App", "Build Widget"])
    }

    @Test func goTestsEveryPackageAndRunsMain() throws {
        #expect(try commands("go") == ["go test ./...", "go build ./...", "go run ."])
    }

    @Test func pythonUsesItsTool() throws {
        #expect(try commands("python-uv") == ["uv sync", "uv run pytest"])
        #expect(try commands("python-poetry") == ["poetry install", "poetry run pytest"])
        #expect(try commands("python-pip") == ["python3 -m pip install -r requirements.txt", "python3 -m pytest"])
    }

    @Test func gradleWrapperAndMaven() throws {
        #expect(try commands("gradle") == ["./gradlew test", "./gradlew build"])
        #expect(try commands("maven") == ["mvn test", "mvn package"])
    }

    @Test func composeUpAndDown() throws {
        #expect(try commands("compose") == ["docker compose up", "docker compose down"])
    }

    @Test func anEmptyFolderSuggestsNothing() throws {
        let empty = FileManager.default.temporaryDirectory.appending(path: "empty-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: empty, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: empty) }
        #expect(ProjectDetector.suggestions(in: empty).isEmpty)
        #expect(ProjectDetector.suggestions(in: empty.appending(path: "missing")).isEmpty)
    }
}
