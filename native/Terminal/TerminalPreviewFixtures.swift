#if NATIVE_PREVIEWS_WIP
import Foundation
import SwiftUI
import Terminal

/// Terminal previews' stores and panels. No engine ever starts, so no shell runs: a terminal itself
/// (libghostty's surface) can't draw in a preview, and tabs show the state that stands in for it.
enum TerminalPreviewFixtures {
    /// A store whose engine fails to start with `error`, with settings kept in memory.
    static func store(
        engine error: TerminalEngineError = .failed("libghostty couldn't create its renderer")
    )
        -> TerminalStore
    {
        TerminalStore(
            preferences: TerminalPreferences(defaults: PreviewUserDefaults()), makeEngine: { .failure(error) })
    }

    /// A panel with a shell tab and two job tabs (a test run and a dev server), the test selected.
    static func panel() -> TerminalPanelModel {
        let folder = URL(filePath: AppPreviewFixtures.nativeFolder, directoryHint: .isDirectory)
        let panel = TerminalPanelModel(workingDirectory: folder, engine: { nil })
        panel.newTab()
        panel.run(
            TerminalJobRequest(
                key: "dev", name: "Dev server", command: "bun run dev", commandLine: "bun run dev", directory: folder))
        panel.run(
            TerminalJobRequest(
                key: "test", name: "Test", command: "swift test --package-path Packages/ACP",
                commandLine: "swift test --package-path Packages/ACP", directory: folder))
        return panel
    }

    static let runningJob = TerminalJob(
        key: "test", name: "Test", command: "swift test --package-path Packages/ACP",
        startedAt: .now.addingTimeInterval(-83))

    static var stoppingJob: TerminalJob {
        var job = runningJob
        job.isStopping = true
        return job
    }

    static func job(ended outcome: TerminalJob.Outcome) -> TerminalJob {
        var job = runningJob
        job.outcome = outcome
        return job
    }

    static let outcomes: [TerminalJob.Outcome] = [
        .exited(status: 0, duration: .seconds(12)),
        .exited(status: 1, duration: .seconds(3)),
        .exited(status: nil, duration: .seconds(41)),
        .stopped(duration: .milliseconds(300)),
    ]

    /// What Import from Ghostty found in a typical config.
    static let ghosttyImport = TerminalImport(
        fontFamily: "JetBrains Mono", fontSize: 13, cursor: TerminalCursor(style: .bar, blinks: false),
        scrollback: .lines(50_000),
        files: [URL(filePath: "/Users/preview/.config/ghostty/config")])
}
#endif
