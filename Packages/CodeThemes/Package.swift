// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "CodeThemes",
    platforms: [.macOS(.v15), .iOS(.v18)],
    products: [
        .library(name: "CodeThemes", targets: ["CodeThemes"]),
        /// The themes and their palettes alone, without highlighting or its grammars: for code that
        /// names themes but never highlights (`NativePolicy`, and the host through it).
        .library(name: "CodeThemeCatalog", targets: ["CodeThemeCatalog"]),
    ],
    // Written out in full, not built from a list, so Dependabot can read and bump each pin.
    dependencies: [
        .package(url: "https://github.com/tree-sitter/swift-tree-sitter", exact: "0.10.0"),
        // SwiftTreeSitter accepts any 0.25.x runtime; pinning it keeps every build on the same one.
        .package(url: "https://github.com/tree-sitter/tree-sitter", exact: "0.25.10"),
        // Grammars, each pinned to an upstream release (docs/decisions.md, "Tree-sitter for
        // highlighting"). Their highlight queries are copied into `Sources/CodeThemes/Queries`, matched
        // to these versions. C++, Kotlin and Ruby stay on the lexer: their grammars were 9.6 MB of the
        // app (docs/app-size.md).
        .package(url: "https://github.com/alex-pinkus/tree-sitter-swift", exact: "0.7.4-with-generated-files"),
        .package(url: "https://github.com/tree-sitter/tree-sitter-typescript", exact: "0.23.2"),
        .package(url: "https://github.com/tree-sitter/tree-sitter-javascript", exact: "0.23.1"),
        .package(url: "https://github.com/tree-sitter/tree-sitter-python", exact: "0.23.6"),
        .package(url: "https://github.com/tree-sitter/tree-sitter-rust", exact: "0.24.2"),
        .package(url: "https://github.com/tree-sitter/tree-sitter-go", exact: "0.25.0"),
        .package(url: "https://github.com/tree-sitter/tree-sitter-json", exact: "0.24.8"),
        .package(url: "https://github.com/tree-sitter/tree-sitter-bash", exact: "0.25.1"),
        .package(url: "https://github.com/tree-sitter-grammars/tree-sitter-yaml", exact: "0.7.0"),
        .package(url: "https://github.com/tree-sitter-grammars/tree-sitter-toml", exact: "0.7.0"),
        .package(url: "https://github.com/tree-sitter/tree-sitter-html", exact: "0.23.2"),
        .package(url: "https://github.com/tree-sitter/tree-sitter-css", exact: "0.23.2"),
        .package(url: "https://github.com/tree-sitter-grammars/tree-sitter-markdown", exact: "0.5.3"),
        .package(url: "https://github.com/tree-sitter/tree-sitter-c", exact: "0.24.2"),
        .package(url: "https://github.com/tree-sitter/tree-sitter-java", exact: "0.23.5"),
    ],
    targets: [
        .target(name: "CodeThemeCatalog"),
        .target(
            name: "CodeThemes",
            dependencies: [
                "CodeThemeCatalog",
                .product(name: "SwiftTreeSitter", package: "swift-tree-sitter"),
                .product(name: "TreeSitter", package: "tree-sitter"),
                .product(name: "TreeSitterSwift", package: "tree-sitter-swift"),
                .product(name: "TreeSitterTypeScript", package: "tree-sitter-typescript"),
                .product(name: "TreeSitterJavaScript", package: "tree-sitter-javascript"),
                .product(name: "TreeSitterPython", package: "tree-sitter-python"),
                .product(name: "TreeSitterRust", package: "tree-sitter-rust"),
                .product(name: "TreeSitterGo", package: "tree-sitter-go"),
                .product(name: "TreeSitterJSON", package: "tree-sitter-json"),
                .product(name: "TreeSitterBash", package: "tree-sitter-bash"),
                .product(name: "TreeSitterYAML", package: "tree-sitter-yaml"),
                .product(name: "TreeSitterTOML", package: "tree-sitter-toml"),
                .product(name: "TreeSitterHTML", package: "tree-sitter-html"),
                .product(name: "TreeSitterCSS", package: "tree-sitter-css"),
                .product(name: "TreeSitterMarkdown", package: "tree-sitter-markdown"),
                .product(name: "TreeSitterC", package: "tree-sitter-c"),
                .product(name: "TreeSitterJava", package: "tree-sitter-java"),
            ],
            resources: [.copy("Queries")]
        ),
        .testTarget(name: "CodeThemesTests", dependencies: ["CodeThemes"]),
    ]
)
