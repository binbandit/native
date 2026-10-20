#if DEBUG
import Foundation

/// The projects and tasks `AppModel.preview` holds: what a developer's sidebar looks like after a
/// week of work across three repositories and three agents.
enum AppPreviewFixtures {
    struct SampleTask {
        let id: String
        let title: String
        let agent: String
        let project: Int
        let minutesAgo: Double
        var state: State = .idle

        enum State {
            case idle, working, needsPermission, doneUnread, failed, pinned, archived
        }
    }

    static let nativeFolder = "/Users/preview/Developer/native"

    static let projectFolders = [
        nativeFolder,
        "/Users/preview/Developer/pier",
        "/Users/preview/Developer/agent-client-protocol",
    ]

    static let tasks: [SampleTask] = [
        SampleTask(
            id: "0199f3a2-queue", title: "Queue follow-ups while a turn runs", agent: "claude-code", project: 0,
            minutesAgo: 4, state: .working),
        SampleTask(
            id: "0199f3a2-flaky", title: "Fix flaky permission request test", agent: "codex", project: 0,
            minutesAgo: 52, state: .needsPermission),
        SampleTask(
            id: "0199f3a2-titles", title: "Session titles from the first prompt", agent: "claude-code", project: 0,
            minutesAgo: 26 * 60, state: .doneUnread),
        SampleTask(
            id: "0199f3a2-wrap", title: "Diff view word wrapping in narrow windows, without breaking the gutter",
            agent: "claude-code", project: 0, minutesAgo: 9 * 24 * 60),
        SampleTask(
            id: "0199f3a2-legacy", title: "Remove the legacy workspace key", agent: "codex", project: 0,
            minutesAgo: 12 * 24 * 60, state: .archived),
        SampleTask(
            id: "0199f3a2-hero", title: "Landing page hero", agent: "cursor", project: 1, minutesAgo: 3 * 60,
            state: .failed),
        SampleTask(
            id: "0199f3a2-retry", title: "Retry uploads when the network drops", agent: "codex", project: 1,
            minutesAgo: 2 * 24 * 60),
        SampleTask(
            id: "0199f3a2-steer", title: "Steering support in the Codex adapter", agent: "codex", project: 2,
            minutesAgo: 4 * 24 * 60, state: .pinned),
        SampleTask(
            id: "0199f3a2-schema", title: "Regenerate the schema types", agent: "claude-code", project: 2,
            minutesAgo: 6 * 24 * 60),
    ]
}
#endif
