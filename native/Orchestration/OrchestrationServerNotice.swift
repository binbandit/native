import SwiftUI

/// Said once, after Native's MCP server had to move off the port it had last time: sessions the host
/// was already running keep the old address until they reload, so they can't use Native's tools
/// meanwhile. Native has already given them the new one; restarting the host reloads them now.
struct OrchestrationServerNotice: View {
    let status: OrchestrationServerStatus
    let onRestartHost: () -> Void

    /// The status to show for `model`'s orchestration plugin, when there's something to say.
    static func status(in model: AppModel) -> OrchestrationServerStatus? {
        model.plugins.plugins.lazy.compactMap { $0.plugin as? OrchestrationPlugin }.first?.status
    }

    var body: some View {
        if let move = status.move {
            NoticeBanner(
                tone: .info,
                systemImage: "point.3.connected.trianglepath.dotted",
                title: "Some tasks can't use Native's tools yet",
                detail:
                    "Tasks that were already running keep Native's old address until they reload, and get the new one then. Restarting the host reloads them now.",
                footnote:
                    "Port \(String(move.from)) was in use when Native opened, so its tools moved to port \(String(move.to))."
            ) {
                Button("Restart Host") {
                    onRestartHost()
                    status.dismiss()
                }
                .buttonStyle(.ds(.secondary))
                .help("Restarts Native's background host. Running turns pick up where they left off.")
                Button("Dismiss", systemImage: "xmark", action: status.dismiss)
                    .buttonStyle(.ds(.ghost, iconOnly: true))
                    .help("Dismiss")
            }
        }
    }
}
