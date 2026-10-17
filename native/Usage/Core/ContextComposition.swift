import ACP
import Foundation

/// A context window split into the segments the breakdown's bar draws, in drawing order: what's in
/// use (built-in, then the user's setup, then the conversation), the free space, and the compaction
/// buffer at the far end, where compaction kicks in.
struct ContextComposition: Hashable {
    struct Segment: Hashable, Identifiable {
        enum Kind: Hashable {
            case used(ContextGroup)
            case free
            case buffer
        }

        let name: String
        let tokens: Int
        let kind: Kind

        var id: String { name }
    }

    let windowTokens: Int
    let usedTokens: Int
    let segments: [Segment]
    /// Tool schemas loaded on demand: listed, but not part of the window.
    let deferred: [ContextReport.Category]

    init(report: ContextReport) {
        let used = report.usedCategories.filter { $0.tokens > 0 }
        let ordered = ContextGroup.allCases.flatMap { group in
            used.filter { ContextGroup(category: $0.name) == group }.map { Segment(name: $0.name, tokens: $0.tokens, kind: .used(group)) }
        }
        var segments = ordered
        let free = report.freeTokens
        if free > 0 {
            segments.append(Segment(name: "Free space", tokens: free, kind: .free))
        }
        for buffer in report.categories where buffer.kind == .buffer && buffer.tokens > 0 {
            segments.append(Segment(name: buffer.name, tokens: buffer.tokens, kind: .buffer))
        }
        windowTokens = report.windowTokens
        usedTokens = report.usedTokens
        self.segments = segments
        deferred = report.deferredCategories.filter { $0.tokens > 0 }
    }

    /// Just the totals, for agents that report no breakdown.
    init(used: Int, window: Int) {
        windowTokens = window
        usedTokens = used
        segments = [
            Segment(name: "In use", tokens: used, kind: .used(.conversation)),
            Segment(name: "Free space", tokens: max(window - used, 0), kind: .free),
        ].filter { $0.tokens > 0 }
        deferred = []
    }

    /// The segments' total, which the bar spans: rounding in the agent's report can leave it a
    /// little off the window size.
    var drawnTokens: Int {
        max(segments.reduce(0) { $0 + $1.tokens }, 1)
    }
}

extension ContextReport {
    /// Whether the report lists any of the user's own setup: MCP tools, memory files, skills, agents.
    var hasContributors: Bool {
        !(mcpTools.isEmpty && memoryFiles.isEmpty && skills.isEmpty && agents.isEmpty)
    }
}
