import Foundation

/// How a repository writes commit subjects, read from its history so drafted messages fit in.
public struct CommitStyle: Hashable, Sendable {
    /// Subjects follow Conventional Commits: `type(scope): summary`.
    public var isConventional: Bool
    /// Scopes the history uses most, most frequent first, e.g. `["web", "composer"]`.
    public var commonScopes: [String]
    /// A few recent subjects to imitate.
    public var examples: [String]

    /// Infers the style from recent subjects. With no history, Conventional Commits.
    public init(subjects: [String], exampleCount: Int = 8) {
        let conventional = subjects.compactMap(Self.conventionalScope)
        // Most of the history, not just a stray `fix:`, before following the convention.
        isConventional = subjects.isEmpty || Double(conventional.count) >= Double(subjects.count) * 0.5
        var counts: [String: Int] = [:]
        for case let scope? in conventional { counts[scope, default: 0] += 1 }
        commonScopes = counts.sorted { $0.value != $1.value ? $0.value > $1.value : $0.key < $1.key }.prefix(5).map(\.key)
        examples = Array(subjects.prefix(exampleCount))
    }

    /// For a Conventional Commits subject, its scope (`nil` inside when it has none); `nil` when
    /// the subject isn't conventional.
    static func conventionalScope(of subject: String) -> String?? {
        guard let colon = subject.firstIndex(of: ":") else { return nil }
        var head = subject[..<colon]
        if head.hasSuffix("!") { head = head.dropLast() }
        var scope: String?
        if let open = head.firstIndex(of: "("), head.hasSuffix(")") {
            scope = String(head[head.index(after: open)..<head.index(before: head.endIndex)])
            head = head[..<open]
        }
        guard !head.isEmpty, head.allSatisfy({ $0.isASCII && $0.isLetter && $0.isLowercase }) else { return nil }
        return .some(scope)
    }
}
