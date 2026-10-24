import ACP
import Foundation
import NativeCommands
import SwiftUI

@testable import Native

/// Exercises Home's real model actions with inert ACP transports, including failed writes.
@main
@MainActor
private struct HomeNextChecks {
    static func main() async throws {
        try await routing()
        try await instructions()
        try await failedDelivery()
        print("PASS: Home Peek routing, shortcut ownership, exact requests, instructions and failed delivery")
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
        app.peekHomeNextTask(task)
        require(app.selection == nil, "Peek leaves Home selected")
        require(app.taskPeek.request?.ask?.session === request.session, "Peek keeps the request's owner")
        require(oldest.isAvailable(CommandContext()), "Peek restores the shared global shortcut contract")
        app.closeTaskPeek()
        require(app.legacyAskShortcutEnabled(in: registry), "Dismissing Peek restores Home's shortcut")
        app.setHomeNextVisible(false)
        require(oldest.isAvailable(CommandContext()), "Leaving Home restores the global shortcut")
        app.setHomeNextVisible(true)
        guard let key = KeyShortcut("⌘Y") else { throw MissingFixture() }
        registry.assign(key, to: .sessionNew, resolving: .replace)
        require(!app.legacyAskShortcutEnabled(in: registry), "Reassigned Command-Y never answers Home")

        guard let allow = call.permission?.options.first(where: { $0.kind == .allowOnce }) else {
            throw MissingFixture()
        }
        try await request.session.answerHomeNextPermission(allow, call: call)
        require(request.session.permissionRequests.isEmpty, "Successful acknowledgement resolves the displayed ask")
        request.session.previewPermissionRequest(command: "swift build")
        do {
            try await request.session.answerHomeNextPermission(allow, call: call)
            require(false, "A stale Home ask must fail")
        } catch {}
        require(request.session.permissionRequests.count == 1, "A stale Home answer leaves the successor intact")

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
        try await session.instructHomeNext("Run only the focused tests", call: call)
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
                try await session.instructHomeNext("Try the focused tests", call: call)
                require(false, "A failed instruction must not report success")
            } catch {}
            require(session.permissionRequests.contains(call), "Failed rejection keeps the exact ask")
            require(
                session.queuedPrompts.map(\.text) == ["An existing follow-up"], "Retry does not duplicate instructions")
        }
        do {
            try await session.answerHomeNextPermission(allow, call: call)
            require(false, "A failed answer must not report success")
        } catch {}
        require(session.permissionRequests.contains(call), "Failed answer keeps the request for retry")
        require(session.draft == "Keep this draft too", "Failed delivery preserves the task draft")
    }

    static func require(_ condition: Bool, _ message: String) {
        guard condition else { print("FAIL: \(message)"); exit(1) }
    }
    struct MissingFixture: Error {}
}
