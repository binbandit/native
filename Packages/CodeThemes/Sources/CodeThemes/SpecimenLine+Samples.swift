extension SpecimenLine {
    public static func sample(language: CodeLanguage? = nil) -> Self {
        let file: String
        let before: [String]
        let after: [String]
        let selected: CodeLanguage
        switch language ?? .typeScript {
        case .swift:
            selected = .swift; file = "Uploader.swift"
            before = ["    if attempt == 3 { throw UploadError.failed }", "    try await Task.sleep(for: .seconds(1))"]
            after = [
                "    if attempt >= 3 { throw UploadError.failed }", "    try await Task.sleep(for: .seconds(delay))",
            ]
        case .python:
            selected = .python; file = "uploader.py"
            before = ["    if attempt == 3: raise UploadError(\"failed\")", "    await asyncio.sleep(1)"]
            after = ["    if attempt >= 3: raise UploadError(\"failed\")", "    await asyncio.sleep(delay)"]
        case .go:
            selected = .go; file = "uploader.go"
            before = ["    if attempt == 3 { return errors.New(\"failed\") }", "    time.Sleep(time.Second)"]
            after = ["    if attempt >= 3 { return errors.New(\"failed\") }", "    time.Sleep(delay * time.Second)"]
        case .rust:
            selected = .rust; file = "uploader.rs"
            before = [
                "    if attempt == 3 { return Err(UploadError::Failed); }", "    sleep(Duration::from_secs(1)).await;",
            ]
            after = [
                "    if attempt >= 3 { return Err(UploadError::Failed); }",
                "    sleep(Duration::from_secs(delay)).await;",
            ]
        default:
            selected = .typeScript; file = "chunker.ts"
            before = [
                "      if (attempt === 3) throw new Error(\"failed\");",
                "      await sleep(1000); // wait before retry",
            ]
            after = [
                "      if (attempt >= 3) throw new Error(\"failed\");",
                "      await sleep(delay); // wait before retry",
            ]
        }
        return Self(
            file: file, project: "pier", language: selected,
            deleted: before.enumerated().map { Line(number: 21 + $0.offset, text: $0.element) },
            added: after.enumerated().map { Line(number: 21 + $0.offset, text: $0.element) }, isSample: true)
    }

    public var languageName: String {
        switch language {
        case .swift: "Swift"
        case .python: "Python"
        case .go: "Go"
        case .rust: "Rust"
        default: "TypeScript"
        }
    }

    public var testCommand: String {
        switch language {
        case .swift: "swift test"
        case .python: "pytest"
        case .go: "go test ./..."
        case .rust: "cargo test"
        default: "pnpm test"
        }
    }
}
