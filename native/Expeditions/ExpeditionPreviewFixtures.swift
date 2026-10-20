#if NATIVE_PREVIEWS_WIP
import Foundation
import NativeAutomation
import NativeExpeditions

/// Expeditions for previews at every stage, driven through their own state machine (`handle`) with
/// replies written here, the way the runner drives them with real sessions. Nothing runs: effects
/// that would make a worktree or a session are answered on the spot with made-up folders and ids.
enum ExpeditionPreviewFixtures {
    static let claude = WorkflowAgent(id: "claude-code", name: "Claude Code", symbol: "asterisk")
    static let codex = WorkflowAgent(id: "codex", name: "Codex", symbol: "terminal")
    static let agents = [claude, codex]
    static let project = URL(filePath: "/Users/preview/Developer/native", directoryHint: .isDirectory)

    static let routeJSON = """
        {
          "summary": "Queue follow-ups in the session model first, then show and manage them in the composer.",
          "legs": [
            {"title": "Queue", "outcome": "Messages sent while a turn runs wait in order and go out when it ends.",
             "assignments": [
               {"id": "queue", "title": "Add the prompt queue", "brief": "In Packages/ACP/Sources/ACP/Prompt, with tests.", "doneWhen": ["swift test passes in Packages/ACP", "Order survives a relaunch"], "assignee": "codex"},
               {"id": "steer", "title": "Send Now steers when the agent can", "brief": "SessionModel+Turns.swift.", "doneWhen": ["Steering agents get the message mid-turn"], "assignee": "codex", "after": ["queue"]}
             ]},
            {"title": "Composer", "outcome": "Queued messages show above the draft, and can be edited, moved and removed.",
             "assignments": [
               {"id": "section", "title": "Queued messages section", "brief": "native/Views/Composer/Sections.", "doneWhen": ["Drag reorders", "Undo puts a removed message back"], "assignee": "claude-code", "after": ["steer"]}
             ]}
          ],
          "questions": ["Should queued messages survive quitting Native?"],
          "assumptions": ["Agents that can't steer queue instead"]
        }
        """

    private static let done = "Implemented and tested.\nGOAL: complete - swift test passes"

    /// Making the base and planning: nothing to review yet.
    static let planning: Expedition = drive { driver in
        driver.send(.start)
    }

    /// The lead's route, waiting for the user.
    static let reviewing: Expedition = drive { driver in
        driver.send(.start)
        driver.end(.lead, "Here's the route.\n\n<route>\n\(routeJSON)\n</route>")
    }

    /// Approved, with the first assignment done and the second working.
    static let underway: Expedition = drive { driver in
        driver.setOut()
        driver.end(.assignment("queue"), done, cost: 0.62)
    }

    /// A builder stopped and is waiting on the user.
    static let needsYou: Expedition = drive { driver in
        driver.setOut()
        driver.end(.assignment("queue"), done, cost: 0.62)
        driver.end(
            .assignment("steer"),
            "I can't tell whether steering should cancel the running tool call.\nGOAL: blocked - needs a decision on cancelling tools",
            cost: 0.31)
    }

    /// Every leg checked, the debrief written.
    static let complete: Expedition = drive { driver in
        driver.setOut()
        driver.end(.assignment("queue"), done, cost: 0.62)
        driver.end(.assignment("steer"), done, cost: 0.40)
        driver.end(.checkpoint("leg-1"), "Looks right.\nVERDICT: pass - ran swift test", cost: 0.12)
        driver.end(.lead, "The route still holds.")
        driver.end(.assignment("section"), done, cost: 0.55)
        driver.end(.checkpoint("leg-2"), "VERDICT: pass - checked drag and undo by hand", cost: 0.10)
        driver.end(
            .lead,
            "## Summary\nFollow-ups now queue while a turn runs, steer when the agent can, and show above the draft.\n\n## Testing\nswift test in Packages/ACP (214 tests)."
        )
    }

    static let all = [planning, reviewing, underway, needsYou, complete]

    private static func drive(_ steps: (inout Driver) -> Void) -> Expedition {
        var driver = Driver()
        steps(&driver)
        return driver.expedition
    }

    /// Answers each effect at once, the way the runner answers it once the host has.
    struct Driver {
        var expedition = Expedition(
            objective: "Queue follow-ups while a turn runs\nAnd let people steer when the agent supports it.",
            project: ExpeditionPreviewFixtures.project, usesWorktree: true,
            crew: Crew(lead: claude, builders: [codex, claude], reviewer: claude),
            budget: ExpeditionBudget(maxCost: 10, maxDuration: 3 * 3_600),
            at: Date.now.addingTimeInterval(-3_600))
        var clock = Date.now.addingTimeInterval(-3_600)

        mutating func send(_ event: ExpeditionEvent) {
            clock += 60
            var pending = expedition.handle(event, at: clock)
            while !pending.isEmpty {
                let effect = pending.removeFirst()
                clock += 1
                switch effect {
                case .prepareBase:
                    pending += expedition.handle(
                        .baseReady(URL(filePath: "/Users/preview/.native/worktrees/native/queue-follow-ups")), at: clock
                    )
                case .createTask(let slot, _, _, _):
                    pending += expedition.handle(.taskCreated(slot, task: UUID()), at: clock)
                case .openPullRequest:
                    let url = URL(string: "https://github.com/binbandit/native/pull/214") ?? project
                    pending += expedition.handle(
                        .pullRequestOpened(WorkflowPullRequestResult(url: url, number: 214)), at: clock)
                case .prompt, .message, .cancelTask:
                    break
                }
            }
        }

        mutating func end(_ slot: CrewSlot, _ reply: String, cost: Double? = nil) {
            send(.turnEnded(slot, outcome: .ended, reply: reply, cost: cost))
        }

        /// Plans and approves the route as proposed.
        mutating func setOut() {
            send(.start)
            end(.lead, "Here's the route.\n\n<route>\n\(routeJSON)\n</route>")
            if let route = expedition.route {
                send(.approve(route))
            }
        }
    }
}
#endif
