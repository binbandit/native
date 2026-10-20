#if DEBUG
import ACP
import Foundation

/// Tasks in every state, for judging the sidebar directions from screenshots:
/// `-sidebarDesignFixture many` fills the instance's first three projects (working, needs approval,
/// failed, done, unread, idle and archived), `-sidebarDesignFixture empty` leaves one finished task.
/// Each task is a preview session (`SessionModel+Preview.swift`: no agent process, nothing reaches
/// an agent), registered so agents' listings keep it. DEBUG only, and only with the argument.
enum SidebarDesignFixture: String {
    case many, empty

    static let launchChoice: Self? = UserDefaults.standard.string(forKey: "sidebarDesignFixture").flatMap(
        Self.init(rawValue:))

    /// Where a task runs when it isn't this Mac: room for remote hosts in the designs, nothing more.
    static var devices: [SessionKey: String] = [:]

    /// Pull requests waiting on the user's review, so the designs show where those go without a
    /// GitHub account behind the instance.
    var reviewRequests: Int {
        switch self {
        case .many: 2
        case .empty: 0
        }
    }

    /// The review count a design shows: GitHub's, or the fixture's while one is loaded.
    static func reviewRequests(_ gitHub: GitHubModel) -> Int {
        max(gitHub.reviewRequestCount, launchChoice?.reviewRequests ?? 0)
    }

    struct Entry {
        enum State {
            case idle, done, doneUnread, archived
            case working(tool: String, kind: String)
            case needsPermission(command: String)
            case failed(notice: String)
            /// The task the window opens on, with a whole turn to look at.
            case selected
        }

        let id: String
        let title: String
        let agent: String
        let project: Int
        let minutesAgo: Double
        let state: State
        var device: String?
    }

    var entries: [Entry] {
        switch self {
        case .many: Self.manyEntries
        case .empty:
            [
                Entry(
                    id: "sd-e1", title: "Add a sentence to CONTRIBUTING", agent: "codex", project: 0, minutesAgo: 3,
                    state: .done)
            ]
        }
    }

    private static let manyEntries: [Entry] = [
        Entry(
            id: "sd-01", title: "Queue follow-ups while a turn runs", agent: "claude-code", project: 0, minutesAgo: 1,
            state: .working(tool: "swift test --filter PromptQueueTests", kind: "execute")),
        Entry(
            id: "sd-02", title: "Fix flaky permission request test", agent: "codex", project: 0, minutesAgo: 7,
            state: .needsPermission(command: "swift test --filter PermissionRequestTests")),
        Entry(
            id: "sd-03", title: "Wrap diff lines at word boundaries", agent: "claude-code", project: 0, minutesAgo: 18,
            state: .selected),
        Entry(
            id: "sd-04", title: "Session titles from the first prompt", agent: "codex", project: 0, minutesAgo: 52,
            state: .doneUnread),
        Entry(
            id: "sd-05", title: "Move the host socket into the channel folder", agent: "codex", project: 0,
            minutesAgo: 130,
            state: .failed(
                notice: "Codex exited mid-turn. Native restarted it; send again to pick up where it left off.")
        ),
        Entry(
            id: "sd-06", title: "Keyboard map for the command palette", agent: "claude-code", project: 0,
            minutesAgo: 26 * 60, state: .idle),
        Entry(
            id: "sd-07", title: "Remove the legacy workspace key", agent: "codex", project: 0, minutesAgo: 4 * 24 * 60,
            state: .idle),
        Entry(
            id: "sd-08", title: "Localize relative times", agent: "claude-code", project: 0, minutesAgo: 6 * 24 * 60,
            state: .idle),
        Entry(
            id: "sd-09", title: "Rename SessionStore to SessionRegistry", agent: "codex", project: 0,
            minutesAgo: 9 * 24 * 60, state: .archived),
        Entry(
            id: "sd-10", title: "Spike: the transcript in a web view", agent: "claude-code", project: 0,
            minutesAgo: 12 * 24 * 60, state: .archived),

        Entry(
            id: "sd-11", title: "Fix the failing initials test", agent: "codex", project: 1, minutesAgo: 3,
            state: .working(tool: "Edit greet.py", kind: "edit")),
        Entry(
            id: "sd-12", title: "Add `--shout` to greet.py", agent: "codex", project: 1, minutesAgo: 5,
            state: .needsPermission(command: "python3 -m unittest")),
        Entry(
            id: "sd-13", title: "Add a slugify helper with tests", agent: "claude-code", project: 1, minutesAgo: 40,
            state: .doneUnread),
        Entry(
            id: "sd-14", title: "Type hints for greet.py", agent: "codex", project: 1, minutesAgo: 2 * 24 * 60,
            state: .idle),
        Entry(
            id: "sd-15", title: "Try pytest instead of unittest", agent: "codex", project: 1, minutesAgo: 8 * 24 * 60,
            state: .archived),

        Entry(
            id: "sd-16", title: "Retry uploads when the network drops", agent: "codex", project: 2, minutesAgo: 9,
            state: .working(tool: "npm test -- uploads", kind: "execute"), device: "studio"),
        Entry(
            id: "sd-17", title: "Landing page hero", agent: "claude-code", project: 2, minutesAgo: 3 * 60,
            state: .failed(notice: "The turn failed: the provider is overloaded. Nothing was changed.")),
        Entry(
            id: "sd-18", title: "AVIF thumbnails in the image pipeline", agent: "codex", project: 2, minutesAgo: 5 * 60,
            state: .doneUnread, device: "studio"),
        Entry(
            id: "sd-19", title: "Dark mode for the marketing site", agent: "claude-code", project: 2,
            minutesAgo: 27 * 60, state: .done),
        Entry(
            id: "sd-20", title: "Regenerate the schema types", agent: "codex", project: 2, minutesAgo: 6 * 24 * 60,
            state: .idle),
        Entry(
            id: "sd-21", title: "Remove the old analytics", agent: "claude-code", project: 2, minutesAgo: 15 * 24 * 60,
            state: .archived),
    ]
}

extension AppModel {
    /// Adds the fixture's tasks to the instance's projects, once its agents are known. Tasks already
    /// registered (a second window) are left alone.
    func applySidebarDesignFixture(_ fixture: SidebarDesignFixture) async {
        // The built-in agents are known shortly after launch.
        var attempts = 0
        while runtime(AgentDefinition.ID(rawValue: "codex")) == nil, attempts < 50 {
            try? await Task.sleep(for: .milliseconds(100))
            attempts += 1
        }
        let projects = projects.all
        var selected: SessionKey?
        for task in fixture.entries where projects.indices.contains(task.project) {
            let project = projects[task.project]
            // Claude Code isn't on every Mac; Codex is the instance's default.
            let agentID = runtime(AgentDefinition.ID(rawValue: task.agent)) == nil ? "codex" : task.agent
            let agent = AgentDefinition.ID(rawValue: agentID)
            let key = SessionKey(agent: agent, id: SessionID(task.id))
            if let device = task.device { SidebarDesignFixture.devices[key] = device }
            guard sessions.session(key) == nil else { continue }
            let date = Date.now.addingTimeInterval(-task.minutesAgo * 60)
            let info = SessionInfo(sessionId: SessionID(task.id), cwd: project.path, title: task.title, updatedAt: date)
            if !catalog.contains(key) {
                catalog.add(info, for: agent, in: project.id)
            }
            guard
                let session = SessionModel.preview(
                    in: self, agent: agentID, id: task.id, cwd: project.path, title: task.title)
            else { continue }
            switch task.state {
            case .idle:
                session.lastActivity = date
            case .done:
                session.previewExchange(task.title, reply: "Done.", endedAgo: task.minutesAgo * 60)
            case .doneUnread:
                session.previewExchange(task.title, reply: "Done.", endedAgo: task.minutesAgo * 60)
                unread.set(key, unread: true)
            case .archived:
                session.previewExchange(task.title, reply: "Done.", endedAgo: task.minutesAgo * 60)
                archivedSessions.set(key, archived: true)
            case .working(let tool, let kind):
                session.previewRunningTurn(task.title)
                session.sidebarDesignToolCall(title: tool, kind: kind, status: "in_progress")
                session.lastActivity = date
            case .needsPermission(let command):
                session.previewRunningTurn(task.title)
                session.previewPermissionRequest(command: command)
                session.lastActivity = date
            case .failed(let notice):
                session.state.appendUserMessage(task.title, at: date.addingTimeInterval(-90))
                session.state.appendNotice(notice, isError: true)
                session.state.endTurn(.error, at: date)
                session.lastStopReason = .error
                session.lastActivity = date
            case .selected:
                session.sidebarDesignWholeTurn(endedAgo: task.minutesAgo * 60)
                selected = key
            }
        }
        if let selected, selection == nil {
            selection = selected
        }
    }
}

extension SessionModel {
    /// A tool call in the transcript, as an agent announces one.
    fileprivate func sidebarDesignToolCall(
        title: String, kind: String, status: String, diff: (path: String, old: String, new: String)? = nil
    ) {
        var call: [String: Any] = [
            "toolCallId": "call_sd_\(UUID().uuidString.prefix(8))", "title": title, "kind": kind, "status": status,
        ]
        if let diff {
            call["content"] = [["type": "diff", "path": diff.path, "oldText": diff.old, "newText": diff.new]]
        }
        guard let data = try? JSONSerialization.data(withJSONObject: call),
            let update = try? JSONDecoder().decode(ToolCallUpdate.self, from: data)
        else { return }
        state.apply(.toolCall(update))
    }

    /// The task the window opens on: a prompt, the agent reading, editing and testing, and its answer.
    fileprivate func sidebarDesignWholeTurn(endedAgo seconds: TimeInterval) {
        let end = Date.now.addingTimeInterval(-seconds)
        state.appendUserMessage(
            "Diff lines wrap mid-word in narrow windows, and the gutter shifts when they do. Wrap at word boundaries and keep the gutter fixed.",
            at: end.addingTimeInterval(-96))
        state.apply(
            .agentMessageChunk(ContentChunk(content: .text("I'll look at how diff rows lay out their text first."))),
            at: end.addingTimeInterval(-90))
        sidebarDesignToolCall(title: "Read DiffLayout.swift", kind: "read", status: "completed")
        sidebarDesignToolCall(
            title: "Search for 'lineBreakMode' in native/DesignSystem/Diff", kind: "search", status: "completed")
        sidebarDesignToolCall(
            title: "Edit DiffRow.swift", kind: "edit", status: "completed",
            diff: (
                path: "\(cwd.path(percentEncoded: false))/native/DesignSystem/Diff/DiffRow.swift",
                old: "Text(line.text)\n    .lineLimit(nil)\n",
                new:
                    "Text(line.text)\n    .lineLimit(nil)\n    .lineBreakStrategy(.standard)\n    .fixedSize(horizontal: false, vertical: true)\n"
            ))
        sidebarDesignToolCall(title: "swift test --filter DiffLayoutTests", kind: "execute", status: "completed")
        state.apply(
            .agentMessageChunk(
                ContentChunk(
                    content: .text(
                        "Lines now wrap at word boundaries, and the gutter keeps its width at any window size. `DiffLayoutTests` passes (14 tests)."
                    ))), at: end)
        state.endTurn(.endTurn, at: end)
        lastStopReason = .endTurn
        lastActivity = end
    }
}
#endif
