import ACP
import Experiments
import Foundation
import NativeCommands
import NativeHostProtocol
import SwiftUI
import TaskList

@testable import Native

/// Exercises Home's real model actions with inert ACP transports, including failed writes.
@main
@MainActor
private struct HomeNextChecks {
    static func main() async throws {
        try await routing()
        try await instructions()
        try await failedDelivery()
        try await failedPeekDelivery()
        startField()
        summaries()
        print(
            "PASS: Home Peek routing, shortcut ownership, exact requests, instructions, failed delivery, "
                + "the start field and summaries")
    }

    static func routing() async throws {
        let app = HomeNextPreviewFixtures.model(.busy)
        let tasks = app.homeNextTasks(retaining: nil)
        guard let task = tasks.first(where: { $0.request?.kind == .approval }),
            let request = task.request, let call = request.call
        else { throw MissingFixture() }
        let registry = CommandRegistry(defaults: PreviewUserDefaults())
        let commands = NativeCommand.taskPeek(model: app)
        guard let oldest = commands.first(where: { $0.id == .taskAnswerOldestAsk }) else { throw MissingFixture() }
        require(app.offersTaskPeek, "Home enables shared Peek without requiring the sidebar experiment")
        require(!app.experiments.value(of: .sidebarNext), "Home does not enable the sidebar redesign")
        app.setHomeNextVisible(true)
        require(app.legacyAskShortcutEnabled(in: registry), "Home's visible ask owns Command-Y")
        require(!oldest.isAvailable(CommandContext()), "Global oldest ask cannot intercept Home's approval")
        require(app.oldestTaskAsk != nil, "The fixture has an oldest ask for rows to advertise")
        require(app.answerShortcutAsk == nil, "No row, on Home's page or past it, advertises Home's keystroke")
        app.peekHomeNextTask(task)
        require(app.selection == nil, "Peek leaves Home selected")
        require(app.taskPeek.request?.ask?.session === request.session, "Peek keeps the request's owner")
        require(oldest.isAvailable(CommandContext()), "Peek restores the shared global shortcut contract")
        require(app.answerShortcutAsk?.id == app.oldestTaskAsk?.id, "Peek restores the oldest ask's keycap")
        app.closeTaskPeek()
        require(app.legacyAskShortcutEnabled(in: registry), "Dismissing Peek restores Home's shortcut")
        app.setHomeNextVisible(false)
        require(oldest.isAvailable(CommandContext()), "Leaving Home restores the global shortcut")
        require(
            app.answerShortcutAsk != nil && app.answerShortcutAsk?.id == app.oldestTaskAsk?.id,
            "Leaving Home restores the oldest ask's keycap")
        app.setHomeNextVisible(true)
        guard let key = KeyShortcut("⌘Y") else { throw MissingFixture() }
        registry.assign(key, to: .sessionNew, resolving: .replace)
        require(!app.legacyAskShortcutEnabled(in: registry), "Reassigned Command-Y never answers Home")

        guard let allow = call.permission?.options.first(where: { $0.kind == .allowOnce }) else {
            throw MissingFixture()
        }
        try await request.session.respondToPermission(allow, call: call)
        require(request.session.permissionRequests.isEmpty, "Successful acknowledgement resolves the displayed ask")
        request.session.previewPermissionRequest(command: "swift build")
        do {
            try await request.session.respondToPermission(allow, call: call)
            require(false, "A stale Home ask must fail")
        } catch {}
        require(request.session.permissionRequests.count == 1, "A stale Home answer leaves the successor intact")
        guard let beforeChange = request.session.permissionRequests.first,
            let update = SessionModel.previewDecode(
                ToolCallUpdate.self,
                "{\"toolCallId\":\"\(beforeChange.id)\",\"rawInput\":{\"command\":\"git push --force origin main\"}}")
        else { throw MissingFixture() }
        request.session.state.apply(.toolCall(update))
        do {
            guard let choice = beforeChange.permission?.options.first(where: { $0.kind == .allowOnce }) else {
                throw MissingFixture()
            }
            try await request.session.respondToPermission(choice, call: beforeChange)
            require(false, "A changed command must not inherit the old approval")
        } catch {}
        require(request.session.permissionRequests.count == 1, "Changed command remains pending for fresh review")

        let child = request.session.addSubagent(SessionID("home-child"))
        app.sessions.register(child)
        child.previewRunningTurn("Child task")
        child.previewPermissionRequest(command: "git status")
        guard let childCall = child.permissionRequests.first,
            let childID = HomeNextApprovalID(session: child, call: childCall),
            let childTask = app.homeNextTasks(retaining: .permission(childID)).first(where: { $0.id == task.id })
        else { throw MissingFixture() }
        app.peekHomeNextTask(childTask)
        require(app.taskPeek.request?.ask?.session === child, "Home Peek captures the selected child request")

        let managed = HomeNextPreviewFixtures.model(.managed)
        guard let managedCall = managed.homeNextTasks(retaining: nil).compactMap({ $0.request?.call }).first else {
            throw MissingFixture()
        }
        require(
            managedCall.permission?.options.contains(where: { $0.kind == .allowAlways }) == false,
            "The strict fixture offers only per-request approval")
        let calm = HomeNextPreviewFixtures.model(.calm)
        require(calm.homeNextTasks(retaining: nil).filter(\.needsYou).count == 4, "Core asks remain with modules off")
    }

    static func instructions() async throws {
        let app = HomeNextPreviewFixtures.model(.busy)
        guard
            let request = app.homeNextTasks(retaining: nil).compactMap(\.request).first(where: { $0.kind == .approval }
            ),
            let call = request.call
        else { throw MissingFixture() }
        let session = request.session
        session.draft = "Keep my separate task draft"
        try await session.instructBeforeDecliningPermission("Run only the focused tests", call: call)
        require(session.permissionRequests.isEmpty, "Instruction declines the captured request")
        require(session.queuedPrompts.map(\.text) == ["Run only the focused tests"], "Instruction queues exactly once")
        require(session.draft == "Keep my separate task draft", "Home's instruction preserves the task draft")
    }

    static func failedDelivery() async throws {
        let app = HomeNextPreviewFixtures.model(.approvalFailure)
        guard
            let request = app.homeNextTasks(retaining: nil).compactMap(\.request).first(where: { $0.kind == .approval }
            ),
            let call = request.call,
            let allow = call.permission?.options.first(where: { $0.kind == .allowOnce })
        else { throw MissingFixture() }
        let session = request.session
        session.draft = "Keep this draft too"
        try await session.submit("An existing follow-up", .queue)
        for _ in 0..<2 {
            do {
                try await session.instructBeforeDecliningPermission("Try the focused tests", call: call)
                require(false, "A failed instruction must not report success")
            } catch {}
            require(session.permissionRequests.contains(call), "Failed rejection keeps the exact ask")
            require(
                session.queuedPrompts.map(\.text) == ["An existing follow-up"], "Retry does not duplicate instructions")
        }
        do {
            try await session.respondToPermission(allow, call: call)
            require(false, "A failed answer must not report success")
        } catch {}
        require(session.permissionRequests.contains(call), "Failed answer keeps the request for retry")
        require(session.draft == "Keep this draft too", "Failed delivery preserves the task draft")
    }

    static func failedPeekDelivery() async throws {
        for instruction in [false, true] {
            let app = HomeNextPreviewFixtures.model(.approvalFailure)
            guard let task = app.homeNextTasks(retaining: nil).first(where: { $0.request?.kind == .approval }),
                let request = task.request, let call = request.call,
                let allow = call.permission?.options.first(where: { $0.kind == .allowOnce })
            else { throw MissingFixture() }
            let session = request.session
            session.draft = "Keep the task draft"
            try await session.submit("An existing follow-up", .queue)
            app.peekHomeNextTask(task)
            guard let peek = app.taskPeek.request, let ask = peek.ask else { throw MissingFixture() }
            for _ in 0..<2 {
                if instruction {
                    do {
                        try await app.instructTaskAsk(ask, text: "Try the focused tests")
                        require(false, "Peek must report an instruction delivery failure")
                    } catch {}
                } else {
                    await app.answerTaskAsk(ask, option: allow)
                }
                require(session.permissionRequests.contains(call), "Failed Peek answer keeps the exact permission")
                require(app.taskPeek.request?.id == peek.id, "Failed Peek answer leaves its presentation open")
                require(!app.taskPeek.isAnswering, "Failed Peek answer permits retry")
                if !instruction {
                    require(app.taskPeek.answerFailure != nil, "Failed Peek approval exposes a recovery error")
                }
                require(
                    session.queuedPrompts.map(\.text) == ["An existing follow-up"], "Peek retry leaves no duplicates")
                require(session.draft == "Keep the task draft", "Peek failure preserves the task draft")
            }
        }
    }

    static func startField() {
        let app = HomeNextPreviewFixtures.model(.busy)
        require(!app.homeNextOwnsNewTask, "Cmd-N keeps its usual meaning while Home is hidden")
        app.setHomeNextVisible(true)
        require(app.homeNextOwnsNewTask, "Cmd-N writes in the start field while Home shows it")
        app.prepareHomeNextStart()
        require(app.quickEntry.project == app.currentProject?.id, "The start field addresses Home's project")
        require(app.quickEntry.agent != nil, "The start field addresses an agent")
        require(app.startHomeNextTask(open: false) == nil, "An empty draft starts nothing")
        let home = app.quickEntry.project
        let other = app.projects.add(URL(filePath: "/tmp/native-home-fixture/pier", directoryHint: .isDirectory))
        app.focusProject(other.id)
        app.prepareHomeNextStart()
        require(app.quickEntry.project == other.id, "An empty draft follows the project Home shows")
        app.quickEntry.draft = "Keep this address"
        if let home { app.focusProject(home) }
        app.prepareHomeNextStart()
        require(app.quickEntry.project == other.id, "A written draft keeps the address it was written to")
        if let home { app.chooseQuickEntryProject(home) }
        app.quickEntry.draft = ""
        app.quickEntry.draft = "Add a retry button to the failed upload toast"
        let before = app.startingTasks.count
        require(app.startHomeNextTask(open: false) == nil, "A missing folder is caught before anything starts")
        require(app.quickEntry.failure != nil, "The start field says why it couldn't start")
        require(
            app.quickEntry.draft == "Add a retry button to the failed upload toast", "A refused start keeps the draft")
        require(app.startingTasks.count == before, "A refused start creates no task")
        app.prepareHomeNextStart()
        require(app.quickEntry.draft.isEmpty == false, "Coming back to Home keeps a draft and its address")
        app.experiments.set(false, for: .homeNext)
        require(!app.homeNextOwnsNewTask, "With Next off, Cmd-N is unchanged")
    }

    static func summaries() {
        let app = HomeNextPreviewFixtures.model(.busy)
        let away = app.homeNextAway(from: .now.addingTimeInterval(-2 * 3_600), to: .now)
        require(away.asked == 3 && away.failed == 1 && away.finished == 0, "Away counts what waits on the user")
        require(away.isNews, "Waiting asks are news")
        require(
            !app.homeNextAway(from: .now.addingTimeInterval(-10 * 3_600), to: .now.addingTimeInterval(-9 * 3_600))
                .isNews, "Nothing from before the absence is counted")

        var clock = Date(timeIntervalSince1970: 1_800_000_000)
        let home = HomeNextModel { clock }
        home.countAway = { HomeNextAway(start: $0, end: $1, finished: 1) }
        home.setInBackground(true)
        clock += 5 * 60
        home.setInBackground(false)
        require(home.away == nil, "Switching apps briefly is not an absence")
        home.setInBackground(true)
        clock += 30 * 60
        home.setDisplayAsleep(true)
        clock += 30 * 60
        home.setDisplayAsleep(false)
        require(home.away == nil, "Waking the display while another app is in front is not a return")
        clock += 30 * 60
        home.setInBackground(false)
        require(home.away?.end.timeIntervalSince(home.away?.start ?? clock) == 90 * 60, "The whole absence counts")

        let limit = HomeNextLimit(
            agent: .init(rawValue: "claude-code"), agentName: "Claude Code", window: "5-hour", resetsAt: nil,
            since: .now, titles: ["Regenerate the schema types"])
        require(limit.title == "Claude Code reached its usage limit", "A limit without a reset says so")
        require(
            limit.detail == "Its 5-hour limit. Regenerate the schema types stopped at it.",
            "A limit names the task it stopped")
        require(HomeNextReviews([]) == nil, "No review requests, no row")
        for summary in HomeNextSummary.allCases {
            require(!summary.isShown(in: PreviewUserDefaults()), "\(summary.title) is off in the calm default")
        }
    }

    static func require(_ condition: Bool, _ message: String) {
        guard condition else { print("FAIL: \(message)"); exit(1) }
    }
    struct MissingFixture: Error {}
}
