import Foundation

/// The curated highlights, newest release last. Add a release when it has something worth showing
/// on first launch: three or four highlights at most, each with a Try It where it helps. Skipped
/// versions are collected, so an entry here is seen by everyone who updates past it. A release lists
/// only what's new since the one before it; 0.1.0, the first, has none, since nobody updates into it.
enum WhatsNewCatalog {
    static let releases: [WhatsNewRelease] = [
        WhatsNewRelease(
            version: WhatsNewVersion("0.2.0"),
            highlights: [
                WhatsNewHighlight(
                    id: "background.keep-running",
                    title: "Agents keep working after you quit",
                    summary: "Tasks run in Native's background host, so they carry on when you quit or close the "
                        + "window, and pick up again after a crash or a restart. Quit Native and Stop Agents "
                        + "(⌃⌥⌘Q) stops them too.",
                    preview: .symbol("moon.zzz"),
                    destination: .settings("background")),
                WhatsNewHighlight(
                    id: "background.while-away",
                    title: "While you were away",
                    summary: "When you come back, one card sums up what your agents finished, what failed and what's "
                        + "waiting for you. Click a task to open it.",
                    preview: .symbol("clock.arrow.circlepath")),
                WhatsNewHighlight(
                    id: "github.task-pull-request",
                    title: "Pull requests on task rows",
                    summary: "A task whose branch has a pull request shows it on its row. Rest the pointer on it to "
                        + "see checks, review and whether it can merge, and open or merge it from there, or press ⌥⌘P.",
                    preview: .symbol("arrow.triangle.pull")),
                WhatsNewHighlight(
                    id: "worktrees.removed",
                    title: "Removed worktrees, handled",
                    summary: "When a task's worktree is deleted outside Native, finished work is archived with Undo, "
                        + "and work that isn't done stays in sight with Restore Worktree to check its branch out again.",
                    preview: .symbol("folder.badge.minus")),
            ])
    ]
}
