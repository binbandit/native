import SwiftUI

/// The shared patterns: notices, errors, usage limits, undo and empty states, plus the formatters.
struct GalleryPatterns: View {
    private static let started = Date.now.addingTimeInterval(-72)

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.lg) {
            NoticeBanner(
                tone: .info, title: "You're offline",
                detail: "Your message is queued and sends when the network returns.")
            ErrorState(
                "The GitHub MCP server didn't start",
                recovery: "Native kept the task running without it.",
                suggestion: "Check the server's command, then retry.",
                details:
                    "Error: spawn npx ENOENT\n    at ChildProcess._handle.onexit (node:internal/child_process:286:19)",
                primary: .init("Retry") {},
                secondary: .init("Disable for This Project") {}
            )
            ForEach(GalleryFixtures.limits) { status in
                LimitBanner(status: status, onResume: {}, onCancelResume: {}, onSnooze: {}, onDismiss: {})
            }
            HStack(spacing: DS.Space.md) {
                ForEach(GalleryFixtures.limits) { status in
                    LimitChip(status: status)
                }
            }
            UndoToast(message: "Archived “Sidebar polish”", onUndo: {}, onDismiss: {})
            EmptyStateView(
                "No pull requests",
                systemImage: "arrow.triangle.pull",
                message: "This project has no open pull requests. Finish a task to open one.",
                actionTitle: "New Task"
            ) {}
            .frame(height: 180)
            .background(.dsSurfaceSunken, in: .rect(cornerRadius: DS.Radius.card))
            ErrorState(
                "Codex isn't installed",
                suggestion: "Install it with npm install -g @openai/codex, then check again.",
                primary: .init("Check Again") {},
                layout: .pane
            )
            .frame(height: 200)
            .background(.dsSurfaceSunken, in: .rect(cornerRadius: DS.Radius.card))
            DiffView(
                path: "native/Views/SidebarView.swift",
                oldText: "let title = \"Tasks\"\nvar body: some View {\n    List {}\n}\n",
                newText:
                    "let title = \"Projects\"\nvar body: some View {\n    List {}\n        .listStyle(.sidebar)\n}\n"
            )
            HStack(spacing: DS.Space.md) {
                ElapsedTimeText(since: Self.started)
                Text(DSFormat.thoughtFor(12))
                Badge("Needs approval", tone: .attention, style: .soft)
                StatusIndicator(status: .paused)
                StatusIndicator(status: .limited)
            }
            .font(.dsBody)
            .foregroundStyle(.dsTextSecondary)
            GalleryFormats()
        }
    }
}

/// Sample output of every `DSFormat` function.
private struct GalleryFormats: View {
    private static let now = Date.now

    private static let rows: [(String, String)] = [
        ("compactAge", DSFormat.compactAge(now.addingTimeInterval(-300), now: now)),
        ("time", DSFormat.time(now.addingTimeInterval(3600 * 20), now: now)),
        ("timeAndCountdown", DSFormat.timeAndCountdown(now.addingTimeInterval(42 * 60), now: now)),
        ("tokens", "\(DSFormat.tokens(103)), \(DSFormat.tokens(228_412)), \(DSFormat.tokens(1_000_000))"),
        ("percent / share", "\(DSFormat.percent(0.42)), \(DSFormat.share(4, of: 1_000))"),
        ("diffStat", DSFormat.diffStat(added: 12, removed: 3)),
        ("duration", "\(DSFormat.duration(8)), \(DSFormat.duration(72)), \(DSFormat.duration(3840))"),
        ("cost", "\(DSFormat.cost(0.42)), \(DSFormat.cost(1234.5)), \(DSFormat.cost(0.004))"),
        ("memory / cpu", "\(DSFormat.memory(1_525_000_000)), \(DSFormat.cpu(0.4)), \(DSFormat.cpu(225))"),
    ]

    var body: some View {
        Grid(alignment: .leading, horizontalSpacing: DS.Space.xl, verticalSpacing: DS.Space.xs) {
            ForEach(Self.rows, id: \.0) { row in
                GridRow {
                    Text(row.0)
                        .font(.dsMonoMicro)
                        .foregroundStyle(.dsTextTertiary)
                    Text(row.1)
                        .font(.dsBody)
                        .foregroundStyle(.dsTextPrimary)
                }
            }
        }
    }
}

#if NATIVE_PREVIEWS_WIP
#Preview("Gallery - Patterns") {
    DSPreviewPair {
        GalleryPatterns()
            .frame(width: 640)
    }
}
#endif
