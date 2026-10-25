import Darwin
import Foundation

/// Explicit delivery of verified bytes, never permission to execute them. No I/O during construction.
public struct PinnedComponentCache: Sendable {
    public enum CacheError: Error, Equatable {
        case invalidRequest, unsafeCache, fetchFailed, storageFailed
    }

    public static let maximumByteCount = 128 * 1024 * 1024
    private let root: URL
    private let component: PinnedComponent
    private let signature: String
    private let key: UpdateSigningKey
    private let artifactURL: URL
    private let fetch: HostUpdateSource.Fetch

    /// The root's parent must already exist and be trusted. Existing roots must be private directories.
    /// Injected transports must bound memory and reject unsuccessful HTTP responses before returning bytes.
    public init(
        root: URL, component: PinnedComponent, signature: String, key: UpdateSigningKey, artifactURL: URL,
        fetch: HostUpdateSource.Fetch? = nil
    ) {
        self.root = root
        self.component = component
        self.signature = signature
        self.key = key
        self.artifactURL = artifactURL
        self.fetch = fetch ?? { try await Self.download($0, limit: component.byteCount) }
    }

    /// Nil means scripting is disabled or an offline cache miss. Corrupt entries fail without replacement.
    public func deliver(scriptingEnabled: Bool, downloadsAllowed: Bool = false) async throws -> Data? {
        guard scriptingEnabled else { return nil }
        try Task.checkCancellation()
        guard root.isFileURL, artifactURL.scheme?.lowercased() == "https", artifactURL.host != nil,
            component.byteCount <= Self.maximumByteCount
        else { throw CacheError.invalidRequest }
        var directory = try openRoot()
        defer { if directory >= 0 { close(directory) } }
        if directory >= 0, let data = try cached(in: directory) {
            try Task.checkCancellation()
            return data
        }
        guard downloadsAllowed else { return nil }
        let data: Data
        do {
            data = try await fetch(artifactURL)
        } catch {
            try Task.checkCancellation()
            if error is CancellationError { throw CancellationError() }
            // Transport errors can contain credential-bearing URLs and response bodies.
            throw CacheError.fetchFailed
        }
        try component.verify(data, signature: signature, key: key)
        try Task.checkCancellation()
        if directory < 0 {
            guard mkdir(root.path, 0o700) == 0 || errno == EEXIST else { throw CacheError.storageFailed }
            directory = try openRoot()
            guard directory >= 0 else { throw CacheError.unsafeCache }
        }
        let temporary = ".pending-\(UUID().uuidString)"
        let file = openat(directory, temporary, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, 0o600)
        guard file >= 0 else { throw CacheError.storageFailed }
        defer {
            close(file)
            unlinkat(directory, temporary, 0)
        }
        do {
            try FileHandle(fileDescriptor: file, closeOnDealloc: false).write(contentsOf: data)
        } catch { throw CacheError.storageFailed }
        try Task.checkCancellation()
        guard renameat(directory, temporary, directory, component.sha256) == 0 else { throw CacheError.storageFailed }
        return data
    }

    private func openRoot() throws -> Int32 {
        let file = open(root.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard file >= 0 else {
            if errno == ENOENT { return -1 }
            throw CacheError.unsafeCache
        }
        var info = stat()
        guard fstat(file, &info) == 0, info.st_uid == geteuid(), info.st_mode & 0o077 == 0 else {
            close(file)
            throw CacheError.unsafeCache
        }
        return file
    }

    private func cached(in directory: Int32) throws -> Data? {
        let file = openat(directory, component.sha256, O_RDONLY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC)
        guard file >= 0 else {
            if errno == ENOENT { return nil }
            throw CacheError.unsafeCache
        }
        defer { close(file) }
        var info = stat()
        guard fstat(file, &info) == 0, info.st_mode & S_IFMT == S_IFREG else { throw CacheError.unsafeCache }
        let data: Data
        do {
            data =
                try FileHandle(fileDescriptor: file, closeOnDealloc: false)
                .read(upToCount: component.byteCount + 1) ?? Data()
        } catch { throw CacheError.storageFailed }
        try component.verify(data, signature: signature, key: key)
        return data
    }

    private static func download(_ url: URL, limit: Int) async throws -> Data {
        let (bytes, response) = try await URLSession.shared.bytes(from: url)
        defer { bytes.task.cancel() }
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode),
            response.url?.scheme?.lowercased() == "https"
        else { throw CacheError.fetchFailed }
        var data = Data()
        for try await byte in bytes {
            guard data.count < limit else { throw CacheError.fetchFailed }
            data.append(byte)
        }
        return data
    }
}
