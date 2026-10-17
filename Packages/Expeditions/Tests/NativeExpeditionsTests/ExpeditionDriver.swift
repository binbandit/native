import Foundation
import NativeAutomation
@testable import NativeExpeditions

/// Drives an expedition the way `ExpeditionRunner` does: makes the base and sessions right away,
/// and records what goes out.
struct ExpeditionDriver {
    var expedition: Expedition
    var clock = Date(timeIntervalSince1970: 2_000_000)
    var tasks: [CrewSlot: UUID] = [:]
    var created: [CrewSlot] = []
    var prompts: [(slot: CrewSlot, text: String)] = []
    var messages: [(slot: CrewSlot, text: String)] = []
    var cancelled: [UUID] = []
    var pullRequests: [WorkflowPullRequestDraft] = []

    static let claude = WorkflowAgent(id: "claude-code", name: "Claude Code")
    static let codex = WorkflowAgent(id: "codex", name: "Codex")

    init(budget: ExpeditionBudget = .unlimited, settings: ExpeditionSettings = ExpeditionSettings()) {
        let crew = Crew(lead: Self.claude, builders: [Self.codex], reviewer: Self.claude)
        expedition = Expedition(
            objective: "Add CSV export to reports\nUsers want spreadsheets.", project: URL(filePath: "/work/app"), usesWorktree: true,
            crew: crew, budget: budget, settings: settings, at: clock)
    }

    mutating func send(_ event: ExpeditionEvent) {
        clock += 10
        var pending = expedition.handle(event, at: clock)
        while !pending.isEmpty {
            let effect = pending.removeFirst()
            clock += 1
            switch effect {
            case .prepareBase:
                pending += expedition.handle(.baseReady(URL(filePath: "/worktrees/app/csv")), at: clock)
            case .createTask(let slot, _, _, _):
                let task = UUID()
                tasks[slot] = task
                created.append(slot)
                pending += expedition.handle(.taskCreated(slot, task: task), at: clock)
            case .prompt(let slot, _, let text):
                prompts.append((slot, text))
            case .message(let slot, _, let text):
                messages.append((slot, text))
            case .cancelTask(let task):
                cancelled.append(task)
            case .openPullRequest(let draft):
                pullRequests.append(draft)
            }
        }
    }

    /// Ends the running turn in `slot` with `reply`.
    mutating func end(_ slot: CrewSlot, _ reply: String?, outcome: TurnOutcome = .ended, cost: Double? = nil) {
        send(.turnEnded(slot, outcome: outcome, reply: reply, cost: cost))
    }

    var lastPrompt: (slot: CrewSlot, text: String)? {
        prompts.last
    }

    func status(_ slot: CrewSlot) -> WorkflowStepStatus? {
        expedition.status(of: slot)
    }

    /// Plans with `route` and approves it as proposed.
    mutating func setOut(_ route: String = ExpeditionDriver.twoLegs) {
        send(.start)
        end(.lead, "Here's the plan.\n\n<route>\n\(route)\n</route>")
        if let proposed = expedition.route {
            send(.approve(proposed))
        }
    }

    static let twoLegs = """
        {
          "summary": "Write the CSV encoder, then wire it into the UI.",
          "legs": [
            {"title": "Encoder", "outcome": "CSV encoding works with tests.",
             "assignments": [
               {"id": "writer", "title": "Add the CSV writer", "brief": "In Sources/Export.", "doneWhen": ["Quotes fields with commas"], "assignee": "codex"},
               {"id": "stream", "title": "Stream large reports", "brief": "Avoid loading everything.", "doneWhen": ["Handles 1M rows"], "assignee": "codex", "after": ["writer"]}
             ]},
            {"title": "UI", "outcome": "Users can export from the toolbar.",
             "assignments": [
               {"id": "button", "title": "Wire the export button", "brief": "Toolbar button.", "doneWhen": ["Button exports"], "assignee": "codex", "after": ["stream"]}
             ]}
          ],
          "questions": ["Quote empty cells?"],
          "assumptions": ["UTF-8 only"]
        }
        """
}
