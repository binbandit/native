import Foundation
import NativeHostProtocol

#if os(Linux)
import Glibc
#else
import Darwin
#endif

/// A local input format. Its digest must arrive through an independent deployment approval.
public struct OfflineAdapterBundle: Codable, Equatable, Sendable {
    public struct Payload: Codable, Equatable, Sendable {
        public let path: String
        public let size: Int
        public let sha256: String

        init(path: String, bytes: Data) throws {
            self.path = path
            self.size = bytes.count
            self.sha256 = try ContentHash.sha256(bytes)
        }
    }

    public enum Failure: Error, Equatable {
        case prohibitedByPolicy, invalidBundle, unsafeFiles, unsupportedPlatform, qualificationMismatch
        case missingArtifact, toolFailed, invalidReceipt, storageFailed
    }

    public let formatVersion: Int
    public let adapterID: String
    public let adapterVersion: String
    public let os: String
    public let architecture: String
    public let nodeVersion: String
    public let npmVersion: String
    public let agentVersion: String
    public let entryPoint: String
    public let requiredInstalledFiles: [String]
    public let payloads: [Payload]

    /// Caller-owned approval, never decoded from the bundle. Tool distributions remain deployment-owned.
    public struct Approval: Sendable {
        public let manifestSHA256: String
        public let packageJSON: Data
        public let packageLock: Data
        public let node: URL
        public let nodeSHA256: String
        public let npmCLI: URL
        public let npmCLISHA256: String
        public let nodeVersion: String
        public let npmVersion: String
        public let agentVersion: String

        public init(
            manifestSHA256: String, packageJSON: Data, packageLock: Data,
            node: URL, nodeSHA256: String, npmCLI: URL, npmCLISHA256: String,
            nodeVersion: String, npmVersion: String, agentVersion: String
        ) {
            self.manifestSHA256 = manifestSHA256
            self.packageJSON = packageJSON
            self.packageLock = packageLock
            self.node = node
            self.nodeSHA256 = nodeSHA256
            self.npmCLI = npmCLI
            self.npmCLISHA256 = npmCLISHA256
            self.nodeVersion = nodeVersion
            self.npmVersion = npmVersion
            self.agentVersion = agentVersion
        }
    }

    static func validate(_ files: [String: Data], approval: Approval) throws -> Self {
        guard let manifest = files["bundle.json"], manifest.count <= 1 << 20,
            try ContentHash.sha256(manifest) == approval.manifestSHA256,
            let bundle = try? JSONDecoder().decode(Self.self, from: manifest), bundle.formatVersion == 1,
            !bundle.adapterID.isEmpty, !bundle.adapterVersion.isEmpty,
            files["package.json"] == approval.packageJSON, files["package-lock.json"] == approval.packageLock
        else { throw Failure.invalidBundle }
        guard bundle.os == platformOS, bundle.architecture == platformArchitecture else {
            throw Failure.unsupportedPlatform
        }
        guard bundle.nodeVersion == approval.nodeVersion, bundle.npmVersion == approval.npmVersion,
            bundle.agentVersion == approval.agentVersion, !bundle.agentVersion.isEmpty
        else { throw Failure.qualificationMismatch }
        let paths = bundle.payloads.map(\.path)
        guard Set(paths).count == paths.count, Set(files.keys) == Set(paths + ["bundle.json"]),
            paths.allSatisfy({ validPath($0) && ($0 == "package.json" || $0 == "package-lock.json" || cachePath($0)) }),
            validPath(bundle.entryPoint), bundle.entryPoint.hasPrefix("node_modules/"),
            !bundle.requiredInstalledFiles.isEmpty,
            Set(bundle.requiredInstalledFiles).count == bundle.requiredInstalledFiles.count,
            bundle.requiredInstalledFiles.contains(bundle.entryPoint),
            bundle.requiredInstalledFiles.allSatisfy({ validPath($0) && $0.hasPrefix("node_modules/") })
        else { throw Failure.invalidBundle }
        for payload in bundle.payloads {
            guard let bytes = files[payload.path], payload.size == bytes.count,
                try ContentHash.sha256(bytes) == payload.sha256
            else { throw Failure.invalidBundle }
        }
        // Auditing remains the caller's job. These checks bind the declared adapter and ensure npm
        // cannot silently discard an optional package that this platform's approval requires.
        guard let root = try JSONSerialization.jsonObject(with: approval.packageJSON) as? [String: Any],
            root["dependencies"] as? [String: String] == [bundle.adapterID: bundle.adapterVersion],
            let lock = try JSONSerialization.jsonObject(with: approval.packageLock) as? [String: Any],
            lock["lockfileVersion"] as? Int == 3,
            let packages = lock["packages"] as? [String: [String: Any]],
            packages["node_modules/" + bundle.adapterID]?["version"] as? String == bundle.adapterVersion
        else { throw Failure.invalidBundle }
        for (path, record) in packages where !path.isEmpty {
            guard validPath(path), path.hasPrefix("node_modules/"), record["link"] == nil else {
                throw Failure.invalidBundle
            }
            if supports(record["os"], value: bundle.os) && supports(record["cpu"], value: bundle.architecture) {
                guard bundle.requiredInstalledFiles.contains(path + "/package.json") else {
                    throw Failure.invalidBundle
                }
            }
        }
        return bundle
    }

    static func validateTools(_ approval: Approval) throws {
        for (url, digest) in [(approval.node, approval.nodeSHA256), (approval.npmCLI, approval.npmCLISHA256)] {
            guard url.isFileURL, url.path.hasPrefix("/"),
                try ContentHash.sha256(readFile(url)) == digest
            else { throw Failure.qualificationMismatch }
        }
        guard FileManager.default.isExecutableFile(atPath: approval.node.path) else {
            throw Failure.qualificationMismatch
        }
    }

    static var platformOS: String {
        #if os(Linux)
        "linux"
        #else
        "darwin"
        #endif
    }

    static var platformArchitecture: String {
        #if arch(arm64)
        "arm64"
        #elseif arch(x86_64)
        "x64"
        #else
        "unsupported"
        #endif
    }

    static func validPath(_ path: String) -> Bool {
        !path.isEmpty && !path.contains("\\") && !path.unicodeScalars.contains(where: { $0.value < 32 })
            && path.split(separator: "/", omittingEmptySubsequences: false).allSatisfy {
                !$0.isEmpty && $0 != "." && $0 != ".."
            }
    }

    private static func cachePath(_ path: String) -> Bool {
        let prefix = "cache/_cacache/content-v2/sha512/"
        guard path.hasPrefix(prefix) else { return false }
        let parts = path.dropFirst(prefix.count).split(separator: "/")
        return parts.map(\.count) == [2, 2, 124]
            && parts.joined().allSatisfy { "0123456789abcdef".contains($0) }
    }

    private static func supports(_ raw: Any?, value: String) -> Bool {
        guard let values = raw as? [String] else { return raw == nil }
        return !values.contains("!" + value)
            && (values.contains(value) || values.contains("any") || values.allSatisfy { $0.hasPrefix("!") })
    }

    static let byteLimit = 256 << 20

    static func readFile(_ url: URL) throws -> Data {
        let file = try ProjectPaths.openForReading(url.path)
        defer { try? file.close() }
        var info = stat()
        guard fstat(file.fileDescriptor, &info) == 0, info.st_mode & 0o6022 == 0,
            info.st_nlink == 1, info.st_size >= 0, info.st_size <= byteLimit
        else { throw Failure.unsafeFiles }
        let bytes = try file.read(upToCount: byteLimit + 1) ?? Data()
        guard bytes.count == info.st_size else { throw Failure.unsafeFiles }
        return bytes
    }

    /// Each lookup is relative to a held directory descriptor, including enumeration. No link is followed.
    static func snapshot(_ root: URL) throws -> [String: Data] {
        let directory = try openDirectory(root)
        defer { close(directory) }
        var files: [String: Data] = [:]
        var total = 0
        try walk(directory, prefix: "", files: &files, total: &total)
        return files
    }

    static func openDirectory(_ root: URL) throws -> Int32 {
        guard root.isFileURL, root.path.hasPrefix("/") else { throw Failure.unsafeFiles }
        var directory = open("/", O_RDONLY | O_DIRECTORY | O_CLOEXEC)
        guard directory >= 0 else { throw Failure.unsafeFiles }
        for name in root.path.split(separator: "/") {
            guard name != ".", name != ".." else { close(directory); throw Failure.unsafeFiles }
            let next = openat(directory, String(name), O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
            guard next >= 0 else { close(directory); throw Failure.unsafeFiles }
            close(directory)
            directory = next
        }
        return directory
    }

    private static func walk(_ directory: Int32, prefix: String, files: inout [String: Data], total: inout Int) throws {
        var info = stat()
        guard fstat(directory, &info) == 0, info.st_mode & 0o6022 == 0,
            let stream = fdopendir(dup(directory))
        else { throw Failure.unsafeFiles }
        defer { closedir(stream) }
        var count = 0
        while true {
            errno = 0
            guard let entry = readdir(stream) else {
                guard errno == 0 else { throw Failure.unsafeFiles }
                break
            }
            let name = withUnsafePointer(to: &entry.pointee.d_name) {
                $0.withMemoryRebound(to: CChar.self, capacity: Int(NAME_MAX) + 1) { String(cString: $0) }
            }
            if name == "." || name == ".." { continue }
            count += 1
            guard validPath(name), !name.contains("/"), files.count < 20_000, prefix.count < 1024 else {
                throw Failure.unsafeFiles
            }
            let descriptor = openat(directory, name, O_RDONLY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC)
            guard descriptor >= 0 else { throw Failure.unsafeFiles }
            defer { close(descriptor) }
            guard fstat(descriptor, &info) == 0, info.st_mode & 0o6022 == 0 else { throw Failure.unsafeFiles }
            let path = prefix + name
            switch info.st_mode & S_IFMT {
            case S_IFDIR:
                try walk(descriptor, prefix: path + "/", files: &files, total: &total)
            case S_IFREG:
                guard info.st_nlink == 1, info.st_size >= 0, info.st_size <= byteLimit - total else {
                    throw Failure.unsafeFiles
                }
                let bytes =
                    try FileHandle(fileDescriptor: descriptor, closeOnDealloc: false)
                    .read(upToCount: byteLimit - total + 1) ?? Data()
                guard bytes.count == info.st_size else { throw Failure.unsafeFiles }
                total += bytes.count
                files[path] = bytes
            default: throw Failure.unsafeFiles
            }
        }
        // An empty undeclared directory is also excess payload.
        guard count > 0 || prefix.isEmpty else { throw Failure.unsafeFiles }
    }
}
