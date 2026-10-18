import Foundation

extension ScriptReference {
    /// The bindings `query` names, best first, for scripts that find their tools rather than read
    /// them all up front. Every word of the query has to appear in a binding's label or summary,
    /// ignoring case; words in the label count for more. An empty query matches every binding, in
    /// label order.
    public static func search(_ bindings: [ScriptBinding], query: String, limit: Int) -> [ScriptBinding] {
        let words = query.lowercased().split(whereSeparator: \.isWhitespace).map(String.init)
        let scored = bindings.compactMap { binding -> (binding: ScriptBinding, score: Int)? in
            let label = binding.label.lowercased()
            let summary = binding.summary?.lowercased() ?? ""
            var score = 0
            for word in words {
                if label.contains(word) {
                    score += 2
                } else if summary.contains(word) {
                    score += 1
                } else {
                    return nil
                }
            }
            return (binding, score)
        }
        return
            scored
            .sorted { $0.score != $1.score ? $0.score > $1.score : $0.binding.label < $1.binding.label }
            .prefix(max(limit, 0))
            .map(\.binding)
    }
}
