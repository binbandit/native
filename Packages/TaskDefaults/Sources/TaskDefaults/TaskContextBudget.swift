/// A preflight estimate, never a promise about an agent's system prompt or deferred tools.
public struct TaskContextBudget: Equatable, Sendable {
    public struct Part: Equatable, Sendable {
        public enum Kind: String, CaseIterable, Sendable { case tools, instructions, skills }
        public let kind: Kind
        public let tokens: Int?
        public let included: Bool

        public init(_ kind: Kind, tokens: Int?, included: Bool = true) {
            self.kind = kind
            self.tokens = tokens.map { max(0, $0) }
            self.included = included
        }
    }

    public let parts: [Part]
    public let window: Int?

    public init(parts: [Part], window: Int? = nil) {
        self.parts = parts
        self.window = window.flatMap { $0 > 0 ? $0 : nil }
    }

    public var knownTokens: Int { parts.filter(\.included).compactMap(\.tokens).reduce(0, +) }
    public var unknownCount: Int { parts.filter { $0.included && $0.tokens == nil }.count }
    public func tokens(for kind: Part.Kind) -> Int {
        parts.filter { $0.included && $0.kind == kind }.compactMap(\.tokens).reduce(0, +)
    }
    public func fraction(for kind: Part.Kind) -> Double {
        guard let window else { return 0 }
        return min(1, Double(tokens(for: kind)) / Double(window))
    }

    /// A deliberately approximate byte heuristic. The UI keeps "about" even when earlier agent
    /// reports contribute counts, because this task has not reported its own context yet.
    public static func estimate(bytes: Int) -> Int { max(0, bytes) / 4 + (max(0, bytes) % 4 == 0 ? 0 : 1) }
}
