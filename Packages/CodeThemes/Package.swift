// swift-tools-version: 6.2
import PackageDescription

/// Tree-sitter grammars, each pinned to an upstream release (docs/decisions.md, "Tree-sitter for highlighting").
/// Their highlight queries are copied into `Sources/CodeThemes/Queries`, matched to these versions. C++, Kotlin
/// and Ruby stay on the lexer: their grammars were 9.6 MB of the app (docs/app-size.md).
let grammars: [(url: String, version: Version, products: [String])] = [
    ("https://github.com/alex-pinkus/tree-sitter-swift", "0.7.4-with-generated-files", ["TreeSitterSwift"]),
    ("https://github.com/tree-sitter/tree-sitter-typescript", "0.23.2", ["TreeSitterTypeScript"]),
    ("https://github.com/tree-sitter/tree-sitter-javascript", "0.23.1", ["TreeSitterJavaScript"]),
    ("https://github.com/tree-sitter/tree-sitter-python", "0.23.6", ["TreeSitterPython"]),
    ("https://github.com/tree-sitter/tree-sitter-rust", "0.24.2", ["TreeSitterRust"]),
    ("https://github.com/tree-sitter/tree-sitter-go", "0.25.0", ["TreeSitterGo"]),
    ("https://github.com/tree-sitter/tree-sitter-json", "0.24.8", ["TreeSitterJSON"]),
    ("https://github.com/tree-sitter/tree-sitter-bash", "0.25.1", ["TreeSitterBash"]),
    ("https://github.com/tree-sitter-grammars/tree-sitter-yaml", "0.7.0", ["TreeSitterYAML"]),
    ("https://github.com/tree-sitter-grammars/tree-sitter-toml", "0.7.0", ["TreeSitterTOML"]),
    ("https://github.com/tree-sitter/tree-sitter-html", "0.23.2", ["TreeSitterHTML"]),
    ("https://github.com/tree-sitter/tree-sitter-css", "0.23.2", ["TreeSitterCSS"]),
    ("https://github.com/tree-sitter-grammars/tree-sitter-markdown", "0.5.3", ["TreeSitterMarkdown"]),
    ("https://github.com/tree-sitter/tree-sitter-c", "0.24.2", ["TreeSitterC"]),
    ("https://github.com/tree-sitter/tree-sitter-java", "0.23.5", ["TreeSitterJava"]),
]

let package = Package(
    name: "CodeThemes",
    platforms: [.macOS(.v15), .iOS(.v18)],
    products: [
        .library(name: "CodeThemes", targets: ["CodeThemes"])
    ],
    dependencies: [
        .package(url: "https://github.com/tree-sitter/swift-tree-sitter", exact: "0.10.0"),
        // SwiftTreeSitter accepts any 0.25.x runtime; pinning it keeps every build on the same one.
        .package(url: "https://github.com/tree-sitter/tree-sitter", exact: "0.25.10"),
    ] + grammars.map { .package(url: $0.url, exact: $0.version) },
    targets: [
        .target(
            name: "CodeThemes",
            dependencies: [
                .product(name: "SwiftTreeSitter", package: "swift-tree-sitter"),
                .product(name: "TreeSitter", package: "tree-sitter"),
            ]
                + grammars.flatMap { grammar in
                    // SwiftPM names a URL dependency after its last path component.
                    let package = String(grammar.url.split(separator: "/").last ?? "")
                    return grammar.products.map { Target.Dependency.product(name: $0, package: package) }
                },
            resources: [.copy("Queries")]
        ),
        .testTarget(name: "CodeThemesTests", dependencies: ["CodeThemes"]),
    ]
)
