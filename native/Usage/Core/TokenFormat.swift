import ACP
import Foundation

/// The one way Native prints token counts: compact with at most one decimal, as Claude Code does
/// ("103", "2k", "228.4k", "1M").
enum TokenFormat {
    static func compact(_ tokens: Int) -> String {
        let thousands = (Double(tokens) / 100).rounded() / 10
        if abs(tokens) < 1_000 { return "\(tokens)" }
        if abs(thousands) < 1_000 { return decimal(thousands) + "k" }
        return decimal((Double(tokens) / 100_000).rounded() / 10) + "M"
    }

    private static func decimal(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(0...1)).grouping(.never))
    }

    /// Keeps the agent's own hedging for estimates ("~300", "< 20").
    static func compact(_ count: ContextReport.TokenCount) -> String {
        switch count.bound {
        case .exact: compact(count.value)
        case .approximate: "~" + compact(count.value)
        case .below: "< " + compact(count.value)
        }
    }

    static func percent(_ fraction: Double) -> String {
        fraction.formatted(.percent.precision(.fractionLength(0)))
    }

    /// One decimal for small shares so a 0.4% row doesn't read as nothing.
    static func share(_ tokens: Int, of total: Int) -> String {
        guard total > 0 else { return "–" }
        let fraction = Double(tokens) / Double(total)
        if tokens > 0, fraction < 0.001 { return "<0.1%" }
        return fraction.formatted(.percent.precision(.fractionLength(fraction < 0.1 ? 1 : 0)))
    }
}
