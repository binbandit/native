import MCPClient
import SwiftUI

/// The status bar's MCP item: the selected session's servers, and whether any needs attention.
/// With no session selected it counts the servers set up in Native.
struct MCPStatusItem: StatusBarItem {
    let model: AppModel
    /// Opens Settings ▸ MCP Servers.
    var onManage: (() -> Void)?

    let id = "mcp-servers"
    let title = "MCP Servers"
    let placement = StatusBarPlacement.trailing
    let order = 40

    var content: some View {
        MCPStatusSegment(model: model, onManage: onManage)
    }
}

private struct MCPStatusSegment: View {
    let model: AppModel
    let onManage: (() -> Void)?

    private var session: SessionModel? {
        model.selection.flatMap(model.session)
    }

    var body: some View {
        if let session, let library = MCPServersPlugin.library(in: model.plugins) {
            let entries = library.entries(forSession: session.clientID)
            let summary = MCPSessionSummary(library: library, entries: entries)
            StatusBarSegment(help: summary.help, accessibilityLabel: "MCP servers", accessibilityValue: summary.help) {
                HStack(spacing: DS.Space.sm) {
                    StatusBarGlyph("server.rack")
                    Text("MCP \(summary.active)")
                    if summary.attention > 0 {
                        StatusDot(color: .dsDanger)
                    }
                }
            } details: {
                MCPSessionPanel(library: library, session: session, entries: entries, onManage: onManage)
            }
        } else if let library = MCPServersPlugin.library(in: model.plugins) {
            let count = library.servers.count { library.mode(of: $0.transport.endpoint.key, in: nil) == .on }
            StatusBarSegment(
                help:
                    "\(count) MCP \(count == 1 ? "server" : "servers") set up in Native. Open a session to see what it loads.",
                accessibilityLabel: "MCP servers",
                accessibilityValue: "\(count) set up in Native"
            ) {
                HStack(spacing: DS.Space.sm) {
                    StatusBarGlyph("server.rack")
                    Text("MCP \(count)")
                }
            } details: {
                PopoverPanel(title: "MCP Servers", systemImage: "server.rack") {
                    EmptyStateView(
                        count == 0 ? "No servers set up in Native" : "\(count) set up in Native",
                        systemImage: "server.rack",
                        message:
                            "Open a session to see every server it has, including the ones its agent loads on its own."
                    ) {
                        if let onManage {
                            Button("Manage MCP Servers…", action: onManage)
                                .buttonStyle(.ds(.secondary, size: .medium))
                        }
                    }
                    .padding(DS.Space.lg)
                }
            }
        }
    }
}
