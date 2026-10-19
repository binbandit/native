import Foundation

/// Both sides of a file change. Either side is `nil` when the file doesn't exist there.
public struct FileVersions: Hashable, Sendable {
    public var path: String
    public var old: Data?
    public var new: Data?

    public init(path: String, old: Data?, new: Data?) {
        self.path = path
        self.old = old
        self.new = new
    }

    /// Either side looks binary, as git judges it: a NUL byte in the first 8000.
    public var isBinary: Bool {
        [old, new].contains { $0.map(Self.isBinary) ?? false }
    }

    public var oldText: String? { old.map { String(decoding: $0, as: UTF8.self) } }
    public var newText: String? { new.map { String(decoding: $0, as: UTF8.self) } }

    /// Both sides' bytes hashed, to tell whether a file changed when its status didn't: an edit
    /// can keep its line counts, like renaming a word. Comparable within one process only.
    public var fingerprint: Int {
        var hasher = Hasher()
        hasher.combine(old)
        hasher.combine(new)
        return hasher.finalize()
    }

    /// The larger side's size in bytes.
    public var size: Int { max(old?.count ?? 0, new?.count ?? 0) }

    static func isBinary(_ data: Data) -> Bool {
        data.prefix(8000).contains(0)
    }
}
