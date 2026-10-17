#if DEBUG
import ACP
import SwiftUI

/// A context source with fixed numbers, for previews.
struct PreviewContextSource: ContextSource {
    var agentName = "Claude Code"
    var usage: Usage?
    var report: ContextReport?
    var reportStatus: ContextReportStatus = .ready(isStale: false)
    var canCompact = true

    func refreshReport() async {}
    func compact() async {}

    static func claude(used: Int) -> PreviewContextSource {
        PreviewContextSource(
            usage: usage(used: used, size: 1_000_000, cost: 0.19),
            report: ContextReport.parse(sampleReport(messages: used - 228_390))
        )
    }

    static let codex = PreviewContextSource(
        agentName: "Codex", usage: usage(used: 61_200, size: 258_400), reportStatus: .unsupported, canCompact: false
    )

    /// Decoded as an agent would send it: `Usage` has no public initializer.
    static func usage(used: Int, size: Int, cost: Double? = nil) -> Usage? {
        let cost = cost.map { #","cost":{"amount":\#($0),"currency":"USD"}"# } ?? ""
        return try? JSONDecoder().decode(Usage.self, from: Data(#"{"used":\#(used),"size":\#(size)\#(cost)}"#.utf8))
    }

    /// Shaped like Claude Code's answer to `/context`, trimmed.
    static func sampleReport(messages: Int) -> String {
        let free = max(1_000_000 - 228_390 - messages - 33_000, 0)
        return """
            ## Context Usage

            **Model:** claude-opus-5-5
            **Tokens:** \(DSFormat.tokens(228_390 + messages)) / 1m

            ### Estimated usage by category

            | Category | Tokens | Percentage |
            |----------|--------|------------|
            | System prompt | 2.1k | 0.2% |
            | System tools | 23.1k | 2.3% |
            | MCP tools | 197.1k | 19.7% |
            | Memory files | 2k | 0.2% |
            | Skills | 4k | 0.4% |
            | Messages | \(DSFormat.tokens(max(messages, 10))) | 0% |
            | Free space | \(DSFormat.tokens(free)) | 0% |
            | Autocompact buffer | 33k | 3.3% |

            ### MCP Tools

            | Tool | Server | Tokens |
            |------|--------|--------|
            | mcp__linear__list_issues | linear | 112.4k |
            | mcp__linear__create_issue | linear | 41k |
            | mcp__github__search_code | github | 43.7k |

            ### Memory Files

            | Type | Path | Tokens |
            |------|------|--------|
            | Project | /Users/me/app/AGENTS.md | 2k |

            ### Skills

            | Skill | Source | Tokens |
            |-------|--------|--------|
            | dataviz | Built-in | ~480 |
            | review | User | ~70 |
            """
    }
}

#Preview("Context breakdown") {
    DSPreviewPair {
        HStack(alignment: .top, spacing: DS.Space.xl) {
            ContextBreakdownView(source: PreviewContextSource.claude(used: 240_000))
            ContextBreakdownView(source: PreviewContextSource.claude(used: 925_000))
            ContextBreakdownView(source: PreviewContextSource.codex)
        }
    }
}

#Preview("Context indicator") {
    DSPreviewPair {
        VStack(alignment: .trailing, spacing: DS.Space.md) {
            ForEach([240_000, 820_000, 960_000], id: \.self) { used in
                HStack {
                    ContextIndicator(source: PreviewContextSource.claude(used: used))
                    ContextIndicator(source: PreviewContextSource.claude(used: used), style: .labeled)
                }
            }
        }
    }
}

#Preview("Context pressure") {
    DSPreviewPair {
        ContextPressureBanner(source: PreviewContextSource.claude(used: 925_000))
            .frame(width: 640)
    }
}
#endif
