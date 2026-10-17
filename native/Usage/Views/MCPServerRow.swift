import ACP
import SwiftUI

/// An MCP server and what its tools cost, opening to the tools themselves, most expensive first.
struct MCPServerRow: View {
    let server: ContextReport.MCPServer

    @State private var isExpanded = false
    @State private var showsAllTools = false
    @State private var isHovered = false

    private static let previewCount = 8

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.dsDisclosure) { isExpanded.toggle() }
            } label: {
                ContributorRow(
                    title: server.name,
                    detail: server.tools.count == 1 ? "1 tool" : "\(server.tools.count) tools",
                    tokens: TokenFormat.compact(server.tokens)
                ) {
                    Image(systemName: "chevron.right")
                        .font(.system(size: DS.Space.md, weight: .semibold))
                        .foregroundStyle(isHovered ? .dsTextSecondary : .dsTextTertiary)
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                }
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .trackHover($isHovered)
            .accessibilityHint(isExpanded ? "Hides its tools" : "Shows its tools")

            if isExpanded {
                let tools = showsAllTools ? server.tools : Array(server.tools.prefix(Self.previewCount))
                ForEach(tools, id: \.name) { tool in
                    ContributorRow(title: tool.shortName, tokens: TokenFormat.compact(tool.tokens), isMono: true)
                        .padding(.leading, DS.Space.md)
                        .help(tool.name)
                }
                if !showsAllTools, server.tools.count > Self.previewCount {
                    ShowAllButton(title: "Show all \(server.tools.count) tools") {
                        showsAllTools = true
                    }
                }
            }
        }
    }
}
