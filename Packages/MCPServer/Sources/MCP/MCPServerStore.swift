#if canImport(CryptoKit)
import Foundation

/// What an MCP server keeps between launches so the URLs it handed out keep working: the secret
/// its tokens are signed with and the port it last listened on. The folder is the user's alone
/// (0700), and so is every file in it (0600).
public struct MCPServerStore: Sendable {
    public let directory: URL

    public init(directory: URL) {
        self.directory = directory
    }

    /// The secret, made the first time it's asked for. A secret that others could have read (a file
    /// with looser permissions, or someone else's) or that's damaged is replaced, since tokens signed
    /// with it can't be trusted; `isNew` says that tokens from earlier launches stop working.
    public func secret() throws -> (secret: Data, isNew: Bool) {
        if let secret = readSecret() {
            return (secret, false)
        }
        return (try replaceSecret(), true)
    }

    /// Replaces the secret with a new one, so tokens signed with the old one stop working.
    @discardableResult
    public func replaceSecret() throws -> Data {
        let secret = MCPTokenSigner.newSecret()
        try write(secret, to: secretURL)
        return secret
    }

    /// Deletes the secret, for when it must not be used again but can't be replaced: the next
    /// `secret()` makes a new one.
    public func forgetSecret() {
        unlink(secretURL.path(percentEncoded: false))
    }

    /// The port the server last listened on.
    public var port: UInt16? {
        guard let text = try? String(contentsOf: portURL, encoding: .utf8) else { return nil }
        return UInt16(text.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    public func savePort(_ port: UInt16) throws {
        try write(Data(String(port).utf8), to: portURL)
    }

    // MARK: - Files

    private var secretURL: URL {
        directory.appending(path: "token-secret")
    }

    private var portURL: URL {
        directory.appending(path: "port")
    }

    private func readSecret() -> Data? {
        let descriptor = open(secretURL.path(percentEncoded: false), O_RDONLY | O_NOFOLLOW | O_CLOEXEC)
        guard descriptor >= 0 else { return nil }
        defer { close(descriptor) }
        var info = stat()
        guard fstat(descriptor, &info) == 0, info.st_uid == getuid(), info.st_mode & 0o077 == 0,
            info.st_size == off_t(MCPTokenSigner.secretSize)
        else { return nil }
        var bytes = [UInt8](repeating: 0, count: MCPTokenSigner.secretSize)
        guard read(descriptor, &bytes, bytes.count) == bytes.count else { return nil }
        return Data(bytes)
    }

    /// Writes `data` readable by the user alone. The file is created 0600 before anything is in it,
    /// then renamed over the old one, so no reader ever sees it half written or more open.
    private func write(_ data: Data, to url: URL) throws {
        try FileManager.default.createDirectory(
            at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o700], ofItemAtPath: directory.path(percentEncoded: false))
        let temporary = directory.appending(path: ".\(url.lastPathComponent)-\(UUID().uuidString)")
            .path(percentEncoded: false)
        let descriptor = open(temporary, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, 0o600)
        guard descriptor >= 0 else { throw Self.posixError() }
        let written = data.withUnsafeBytes { Darwin.write(descriptor, $0.baseAddress, $0.count) }
        let isSynced = fsync(descriptor) == 0
        close(descriptor)
        guard written == data.count, isSynced, rename(temporary, url.path(percentEncoded: false)) == 0 else {
            let error = Self.posixError()
            unlink(temporary)
            throw error
        }
    }

    private static func posixError() -> POSIXError {
        POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
    }
}
#endif
