#if os(macOS)
import CryptoKit
import Foundation

extension AgentCommand {
    /// This command without npm in the middle, when it's `npx` running an exact package version
    /// that npx has already installed. Run through npx, npm stays alive as the adapter's parent for
    /// as long as it runs (a Node process of about 50 MB doing nothing) and costs a few hundred
    /// milliseconds of starting up at every launch. This runs the binary npx would have run, from
    /// npx's own install, with the `PATH` npx gives it. Anything else (a range or tag, other npx
    /// options, a version npx hasn't installed yet) stays as it is, and npx installs it as usual.
    public func skippingNpx(fileManager: FileManager = .default) -> AgentCommand {
        guard let launch = NpxLaunch(self), let binaries = launch.installedBinaries(fileManager: fileManager) else {
            return self
        }
        var environment = environment
        environment["PATH"] = [binaries.path(percentEncoded: false), environment["PATH"]].compactMap(\.self)
            .joined(separator: ":")
        return AgentCommand(
            executable: binaries.appending(path: launch.binary).path(percentEncoded: false),
            arguments: launch.arguments,
            environment: environment,
            workingDirectory: workingDirectory
        )
    }
}

/// `npx [--yes] <name>@<exact version> [arguments…]`, and where npx installs it: npm keeps each
/// npx package set in `<cache>/_npx/<first 16 hex digits of the SHA-512 of the spec>`.
struct NpxLaunch: Equatable {
    var name: String
    var version: String
    var arguments: [String]
    var cache: URL

    init?(_ command: AgentCommand) {
        guard URL(filePath: command.executable).lastPathComponent == "npx" else { return nil }
        var rest = command.arguments[...]
        while let option = rest.first, option.hasPrefix("-") {
            guard option == "--yes" || option == "-y" else { return nil }
            rest = rest.dropFirst()
        }
        guard let spec = rest.first, let at = spec.lastIndex(of: "@"), at != spec.startIndex else { return nil }
        let version = String(spec[spec.index(after: at)...])
        guard version.wholeMatch(of: /\d+\.\d+\.\d+(-[0-9A-Za-z.-]+)?/) != nil else { return nil }
        name = String(spec[..<at])
        self.version = version
        arguments = Array(rest.dropFirst())
        let home = command.environment["HOME"].map { URL(filePath: $0, directoryHint: .isDirectory) } ?? .homeDirectory
        cache =
            command.environment["npm_config_cache"].map { URL(filePath: $0, directoryHint: .isDirectory) }
            ?? home.appending(path: ".npm", directoryHint: .isDirectory)
    }

    var folder: URL {
        let digest = SHA512.hash(data: Data("\(name)@\(version)".utf8))
        let hash = digest.map { String(format: "%02x", $0) }.joined().prefix(16)
        return cache.appending(path: "_npx/\(hash)", directoryHint: .isDirectory)
    }

    /// The binary npx runs, by npm's rule: the only one the package has, or the one named after it.
    var binary: String {
        name.split(separator: "/").last.map(String.init) ?? name
    }

    /// The installed `node_modules/.bin`, when it holds exactly this version and its binary.
    func installedBinaries(fileManager: FileManager) -> URL? {
        let modules = folder.appending(path: "node_modules", directoryHint: .isDirectory)
        let manifestURL = modules.appending(path: name).appending(path: "package.json")
        guard let data = try? Data(contentsOf: manifestURL),
            let manifest = try? JSONDecoder().decode(Manifest.self, from: data),
            manifest.version == version, manifest.binaries(unscopedName: binary).contains(binary)
        else { return nil }
        let binaries = modules.appending(path: ".bin", directoryHint: .isDirectory)
        guard fileManager.isExecutableFile(atPath: binaries.appending(path: binary).path(percentEncoded: false)) else {
            return nil
        }
        return binaries
    }

    private struct Manifest: Decodable {
        var version: String
        var bin: Bin?

        enum Bin: Decodable {
            case single(String)
            case named([String: String])

            init(from decoder: any Decoder) throws {
                let container = try decoder.singleValueContainer()
                if let path = try? container.decode(String.self) {
                    self = .single(path)
                } else {
                    self = .named(try container.decode([String: String].self))
                }
            }
        }

        /// The binary names npx would pick from: one, or the one named after the package.
        func binaries(unscopedName: String) -> [String] {
            switch bin {
            case .single: [unscopedName]
            case .named(let binaries) where Set(binaries.values).count == 1: binaries.keys.sorted().prefix(1).map(\.self)
            case .named(let binaries): binaries.keys.filter { $0 == unscopedName }
            case nil: []
            }
        }
    }
}
#endif
