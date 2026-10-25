import Foundation

/// The Node and npm already installed on this machine, for fixture tests that run the real tools.
/// Version-manager shims on PATH are skipped: given a scratch HOME, some download a whole runtime
/// instead of running the installed one, and these tests never fetch a tool.
struct LocalNodeTools {
    /// The Node executable itself, with links resolved.
    let node: URL
    /// npm's JavaScript entry, which `node` runs directly.
    let npmCLI: URL
    /// This Node's directory, then the `npm` link's, for tests that run `npm` by name.
    let path: String

    static let installed: Self? = {
        let search = (ProcessInfo.processInfo.environment["PATH"] ?? "").split(separator: ":").map {
            URL(filePath: String($0))
        }
        func find(_ name: String, accepting accept: (URL) -> Bool) -> (directory: URL, file: URL)? {
            search.lazy.map { ($0, $0.appending(path: name).resolvingSymlinksInPath()) }
                .first { FileManager.default.isExecutableFile(atPath: $0.1.path) && accept($0.1) }
        }
        // A multi-call shim resolves to its own name, and a script shim starts with `#!`.
        guard
            let node = find(
                "node",
                accepting: { file in
                    file.lastPathComponent == "node"
                        && (try? FileHandle(forReadingFrom: file).read(upToCount: 2)) != Data("#!".utf8)
                }),
            let npm = find("npm", accepting: { $0.lastPathComponent == "npm-cli.js" })
        else { return nil }
        let directories = [node.file.deletingLastPathComponent().path, npm.directory.path, "/usr/bin", "/bin"]
        return Self(node: node.file, npmCLI: npm.file, path: directories.joined(separator: ":"))
    }()
}
