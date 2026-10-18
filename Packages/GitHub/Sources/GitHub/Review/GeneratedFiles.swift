import Foundation

/// Files nobody reviews line by line: lockfiles, minified bundles, generated code and snapshots.
/// GitHub folds these (from linguist's rules); this follows the common cases, by path alone.
public enum GeneratedFiles {
    static let names: Set<String> = [
        "package-lock.json", "npm-shrinkwrap.json", "yarn.lock", "pnpm-lock.yaml", "bun.lock",
        "bun.lockb",
        "Cargo.lock", "Gemfile.lock", "poetry.lock", "Pipfile.lock", "uv.lock", "composer.lock",
        "go.sum",
        "Podfile.lock", "Package.resolved", "flake.lock", "mix.lock", "pubspec.lock", "gradle.lockfile",
    ]

    static let suffixes = [
        ".min.js", ".min.css", ".min.map", ".js.map", ".css.map", ".pb.go", "_pb2.py", "_pb2_grpc.py",
        ".pb.swift",
        ".generated.swift", ".g.dart", ".freezed.dart", ".designer.cs", ".snap",
        ".xcodeproj/project.pbxproj",
    ]

    static let directories = [
        "node_modules/", "dist/", "vendor/", "__snapshots__/", "Generated/", ".yarn/releases/",
    ]

    public static func isGenerated(_ path: String) -> Bool {
        let name = (path as NSString).lastPathComponent
        if names.contains(name) { return true }
        if suffixes.contains(where: path.hasSuffix) { return true }
        let wrapped = "/" + path
        return directories.contains { wrapped.contains("/" + $0) }
    }
}
