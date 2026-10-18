import Foundation

/// The curated highlights, newest release last. Add a release when it has something worth showing
/// on first launch: three or four highlights at most, each with a Try It where it helps. Skipped
/// versions are collected, so an entry here is seen by everyone who updates past it.
enum WhatsNewCatalog {
    static let releases: [WhatsNewRelease] = [
        WhatsNewRelease(
            version: WhatsNewVersion("0.2.0"),
            highlights: [
                WhatsNewHighlight(
                    id: "updates.toolbar-button",
                    title: "Updates, one click away",
                    summary: "Native downloads updates in the background. When one is ready, Update appears beside the "
                        + "sidebar toggle; your agents keep working while Native restarts.",
                    preview: .symbol("arrow.down.circle"),
                    destination: .settings("updates")),
                WhatsNewHighlight(
                    id: "updates.channels",
                    title: "Beta and Nightly",
                    summary: "Follow betas from Settings ▸ Updates, or install Native Nightly beside Native to try "
                        + "tonight's build without touching your daily one.",
                    preview: .symbol("moon.stars"),
                    destination: .settings("updates")),
                WhatsNewHighlight(
                    id: "terminal.panel",
                    title: "A terminal in every task",
                    summary: "Open a terminal in the task's folder without leaving Native, styled to match your theme.",
                    preview: .symbol("apple.terminal"),
                    destination: .settings("terminal")),
            ]),
        WhatsNewRelease(
            version: WhatsNewVersion("0.3.0"),
            highlights: [
                WhatsNewHighlight(
                    id: "mcp.servers",
                    title: "MCP servers, checked",
                    summary: "See every MCP server your agents use, whether it's healthy, and what it costs in context.",
                    preview: .symbol("server.rack"),
                    destination: .settings("mcp-servers")),
                WhatsNewHighlight(
                    id: "keep-awake",
                    title: "Keep Awake while agents work",
                    summary: "Your Mac stays awake while a task is running, and sleeps as usual once it's done.",
                    preview: .symbol("cup.and.saucer"),
                    destination: .settings("keepAwake")),
            ]),
    ]
}
