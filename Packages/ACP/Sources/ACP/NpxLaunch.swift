#if os(macOS) || os(Linux)
import Foundation

#if canImport(CryptoKit)
import CryptoKit
#endif

extension AgentCommand {
    /// This command without npm in the middle, when it's `npx` running an exact package version
    /// that npx has already installed. Run through npx, npm stays alive as the adapter's parent for
    /// as long as it runs (a Node process of about 50 MB doing nothing) and costs a few hundred
    /// milliseconds of starting up at every launch. This runs the binary npx would have run, from
    /// npx's own install, with the `PATH` npx gives it. Anything else (a range or tag, other npx
    /// options, a version npx hasn't installed yet) stays as it is, and npx installs it as usual.
    ///
    /// Without CryptoKit (Linux) the command always stays as it is: npm names its install folders
    /// by a SHA-512, and finding one isn't worth a cryptography dependency for ACP.
    public func skippingNpx(fileManager: FileManager = .default) -> AgentCommand {
        #if canImport(CryptoKit)
        guard let launch = NpxLaunch(self), let binary = launch.installedBinary(fileManager: fileManager) else {
            return self
        }
        var environment = environment
        // The folder npx adds to the PATH, which holds the package's dependencies' binaries too.
        let binaries = String(binary.deletingLastPathComponent().path(percentEncoded: false).dropLast())
        environment["PATH"] = [binaries, environment["PATH"]].compactMap(\.self).joined(separator: ":")
        return AgentCommand(
            executable: binary.path(percentEncoded: false),
            arguments: launch.arguments,
            environment: environment,
            workingDirectory: workingDirectory
        )
        #else
        self
        #endif
    }
}

#if canImport(CryptoKit)
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

    /// The installed binary npx would run, when npx's folder holds exactly this version.
    func installedBinary(fileManager: FileManager) -> URL? {
        let modules = folder.appending(path: "node_modules", directoryHint: .isDirectory)
        let manifestURL = modules.appending(path: name).appending(path: "package.json")
        guard let data = try? Data(contentsOf: manifestURL),
            let manifest = try? JSONDecoder().decode(Manifest.self, from: data), manifest.version == version,
            let binary = manifest.binary(unscopedName: name.split(separator: "/").last.map(String.init) ?? name)
        else { return nil }
        let url = modules.appending(path: ".bin").appending(path: binary)
        return fileManager.isExecutableFile(atPath: url.path(percentEncoded: false)) ? url : nil
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

        /// npm's rule: the package's only binary, or the one named after it.
        func binary(unscopedName: String) -> String? {
            switch bin {
            case .single: unscopedName
            case .named(let binaries) where binaries.count == 1: binaries.keys.first
            case .named(let binaries) where binaries[unscopedName] != nil: unscopedName
            default: nil
            }
        }
    }
}
#endif
#endif
