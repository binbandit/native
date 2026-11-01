import Foundation

/// Source identity is deliberately exact: a newer file is never treated as the original anchor.
public struct PromptDiffComment: Equatable, Sendable, Codable, Identifiable {
    public let id: UUID
    public let task: UUID
    public let scope: String
    public let fingerprint: String
    public var body: String
    public var isEarlierVersion: Bool

    public init(
        id: UUID = UUID(), task: UUID, scope: String, fingerprint: String, body: String,
        isEarlierVersion: Bool = false
    ) {
        self.id = id
        self.task = task
        self.scope = scope
        self.fingerprint = fingerprint
        self.body = body
        self.isEarlierVersion = isEarlierVersion
    }

    /// Stable across launches and platforms, unlike Swift's randomized Hasher. This is an identity
    /// check, not a security digest; compare the selected text as well before reusing an anchor.
    public static func fingerprint(old: String?, new: String) -> String {
        var hash: UInt64 = 14_695_981_039_346_656_037
        for byte
            in ((old == nil ? "absent:" : "before:\(old?.utf8.count ?? 0):" + (old ?? "")) + "after:\(new.utf8.count):"
            + new).utf8
        {
            hash = (hash ^ UInt64(byte)) &* 1_099_511_628_211
        }
        return String(hash, radix: 16)
    }

    public func matches(scope: String, fingerprint: String) -> Bool {
        self.scope == scope && self.fingerprint == fingerprint && !isEarlierVersion
    }
}
