#if DEBUG
import ACP
import Foundation
import SessionTools

enum TaskWellPreviewFixtures {
    static var states: [TaskWellContent] {
        [
            TaskWellContent(status: .idle, agent: "Codex"),
            TaskWellContent(status: .starting, agent: "Codex", verb: "Starting"),
            TaskWellContent(status: .working, agent: "Codex", verb: "Stopping"),
            TaskWellContent(status: .working, agent: "Codex", verb: "Reconnecting"),
            TaskWellContent(
                status: .working, agent: "Claude Code", verb: "Running", object: "swift test",
                progress: .init(completed: 9, total: 12)),
            TaskWellContent(
                status: .working, agent: "A very long agent name", verb: "Reading",
                object: "Sources/Native/PromptQueueTests.swift"),
            TaskWellContent(
                status: .needsPermission, agent: "Codex", verb: "Waiting on you",
                object: "to overwrite main on github.com", attentionSince: .now),
            TaskWellContent(status: .done, agent: "Codex", outcome: outcome, showsReview: true),
            TaskWellContent(status: .idle, agent: "Codex", outcome: outcome, showsReview: true),
            TaskWellContent(status: .failed, agent: "Codex", verb: "Turn failed", object: "See the conversation"),
            TaskWellContent(status: .cancelled, agent: "Codex", verb: "Stopped"),
        ]
    }

    static var outcome: TurnSummary {
        var summary = TurnSummary(items: [TranscriptItem]())
        summary.changedFiles = [
            .init(path: "DiffRow.swift", added: 12, removed: 2),
            .init(path: "DiffLayout.swift", added: 3),
            .init(path: "DiffLayoutTests.swift", added: 2),
        ]
        return summary
    }

    /// A tool a plugin adds (`NativePlugin.sessionTools`), as the plugin registry hands it over.
    static var pluginTool: SessionToolContribution {
        var tool = SessionToolContribution(
            spec: SessionToolSpec(id: "acme.tickets", places: [.side, .fact, .off], defaultPlace: .side),
            title: "Release verification and acceptance checks", systemImage: "checklist",
            summary: "Check narrow Changes layouts and keyboard navigation before landing.",
            fact: { _ in SessionToolFact(text: "ACME-142 · In review") })
        tool.pluginName = "Acme Tickets"
        return tool
    }

    static func registryWithPluginTool() -> SessionToolRegistry {
        let registry = SessionToolRegistry(defaults: PreviewUserDefaults())
        var runbook = SessionToolContribution(
            spec: SessionToolSpec(id: "acme.runbook", places: [.side, .off], defaultPlace: .off),
            title: "Runbook", systemImage: "book.closed", summary: "The team's runbook, beside the conversation.")
        runbook.pluginName = "Acme Tickets"
        registry.setPluginTools([pluginTool, runbook])
        return registry
    }

    static let title = TaskWellTitleFacts(
        title: "Wrap diff lines at word boundaries", project: "native", branch: "wrap-diff-lines", agent: "Codex",
        model: "6.1 Sol")
    static let remoteTitle = TaskWellTitleFacts(
        title: "Retry uploads when the network drops", project: "pier", branch: "retry-uploads", machine: "elara",
        agent: "Claude Code", model: "Opus 5.5")
    static let longTitle = TaskWellTitleFacts(
        title: "Landing page hero loads blurry first on slow connections", project: "pier",
        branch: "binbandit/landing-hero-progressive-images", machine: "Build Mac", agent: "Claude Code",
        model: "Sonnet 5.5")
    static let managedTitle = TaskWellTitleFacts(
        title: "Round half-even in quarterly totals", project: "ledger-core", branch: "rounding-half-even",
        agent: "Codex", model: "gpt-6.1-sol", isWorkerManaged: true,
        management: "Managed by Northwind Federal IT · #it-help")
}
#endif
