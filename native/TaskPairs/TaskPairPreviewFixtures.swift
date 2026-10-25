#if DEBUG
import ACP
import Experiments
import Foundation
import Git
import SwiftUI

/// A brief sent to Codex and Claude Code, both done, for previews: never runs git or an agent.
enum TaskPairPreviewFixtures {
    static let title = "Offline time on the device pill"
    static let codex = SessionKey(agent: AgentDefinition.ID(rawValue: "codex"), id: SessionID("pair-codex"))
    static let claude = SessionKey(agent: AgentDefinition.ID(rawValue: "claude-code"), id: SessionID("pair-claude"))

    static func app() -> AppModel {
        let experiments = ExperimentStore(catalog: .native, storage: InMemoryExperimentStorage())
        experiments.set(true, for: .composeTask)
        let app = AppModel(
            plugins: PluginRegistry(builtIns: [BuiltInPlugins.claudeCode, BuiltInPlugins.codex]),
            defaults: PreviewUserDefaults(), catalogURL: nil, experiments: experiments)
        _ = app.runtimes.sync()
        let project = app.projects.add(URL(filePath: "/sample/native", directoryHint: .isDirectory))
        for key in [codex, claude] {
            app.catalog.add(
                SessionInfo(sessionId: key.id, cwd: "/sample/native-\(key.id.rawValue)", title: title),
                for: key.agent, in: project.id)
        }
        app.catalog.add(
            SessionInfo(
                sessionId: SessionID("other"), cwd: "/sample/native", title: "Queue follow-ups while a turn runs"),
            for: codex.agent, in: project.id)
        return app
    }

    static func pair(in app: AppModel) -> TaskPair {
        if let pair = app.taskPairs.pair(containing: claude) { return pair }
        app.taskPairs.add([codex, claude])
        return app.taskPairs.pair(containing: claude) ?? TaskPair(id: UUID(), tasks: [codex, claude])
    }

    /// Codex still on its turn.
    static func workingPair(in app: AppModel) -> TaskPair {
        let pair = pair(in: app)
        SessionModel.preview(
            in: app, agent: "codex", id: codex.id.rawValue, cwd: "/sample/native-pair-codex", title: title)?
            .previewRunningTurn(title)
        return pair
    }

    /// Claude Code's version kept over Codex's.
    static func keptApp() -> AppModel {
        let app = app()
        let pair = pair(in: app)
        app.taskPairs.setKept(claude, in: pair.id)
        return app
    }

    static func ready() -> TaskPairComparison {
        TaskPairComparison(fixed: .ready(base: "base", versions: [version(claude), version(codex)]))
    }

    private static func version(_ key: SessionKey) -> TaskPairComparison.Version {
        let isClaude = key == claude
        let changes =
            isClaude
            ? [
                TreeChange(
                    path: "native/Hosts/HostDevicePicker.swift", kind: .modified,
                    stats: LineStats(additions: 10, deletions: 4)),
                TreeChange(
                    path: "native/Hosts/HostDevicePill.swift", kind: .modified,
                    stats: LineStats(additions: 14, deletions: 2)),
            ]
            : [
                TreeChange(
                    path: "native/Hosts/HostDevicePicker.swift", kind: .modified,
                    stats: LineStats(additions: 3, deletions: 9)),
                TreeChange(path: "native/Hosts/HostDevicePill.swift", kind: .modified, stats: LineStats(additions: 6)),
                TreeChange(path: "native/Hosts/OfflineAgeText.swift", kind: .added, stats: LineStats(additions: 22)),
            ]
        return TaskPairComparison.Version(
            task: key, agent: isClaude ? "Claude Code" : "Codex",
            branch: isClaude ? "offline-time-pill" : "offline-time-pill-2", target: key.id.rawValue, changes: changes,
            diff: { change, _ in
                .text(GitDiffText(path: change.path, oldText: before, newText: isClaude ? claudeAfter : codexAfter))
            })
    }

    private static let before = """
        HStack(spacing: DS.Space.sm) {
            HostGlyph(look: look, size: HostsMetrics.rowGlyph)
            Text(name)
            if !availability.isOnline {
                HostAvailabilityMark(availability: availability)
            }
        }
        """
    private static let claudeAfter = """
        HStack(spacing: DS.Space.sm) {
            HostGlyph(look: look, size: HostsMetrics.rowGlyph)
            Text(name)
            if !availability.isOnline, let lastSeen {
                HostAvailabilityMark(availability: availability)
                Text("Offline · \\(DSFormat.compactAge(lastSeen))")
                    .foregroundStyle(.dsTextTertiary)
            }
        }
        """
    private static let codexAfter = """
        HStack(spacing: DS.Space.sm) {
            HostGlyph(look: look, size: HostsMetrics.rowGlyph)
            Text(name)
            if !availability.isOnline {
                HostAvailabilityMark(availability: availability)
                OfflineAgeText(since: selected?.lastSeen)
            }
        }
        """
}
#endif
