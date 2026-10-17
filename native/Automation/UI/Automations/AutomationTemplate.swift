import Foundation
import NativeAutomation

/// A starting point for a new automation, after Conductor's suggested routines.
struct AutomationTemplate: Identifiable {
    let id: String
    let name: String
    let summary: String
    let symbol: String
    let triggers: [AutomationTrigger]
    let action: AutomationAction

    func automation(in project: URL, at date: Date) -> Automation {
        Automation(name: name, triggers: triggers, action: action, project: project, createdAt: date)
    }

    static let all: [AutomationTemplate] = [
        AutomationTemplate(
            id: "fix-ci", name: "Fix failing CI",
            summary: "When CI fails on one of your pull requests, an agent finds the cause and fixes it.",
            symbol: "xmark.octagon", triggers: [.event(.checksFailed)],
            action: .goal(
                objective: "CI is failing on the pull request below. Check out its branch, find the cause, fix it, and push the fix once the failing checks pass locally. If the failure isn't caused by the change (a flaky test, an outage), say so instead of changing code.",
                budget: GoalBudget(maxIterations: 6)
            )
        ),
        AutomationTemplate(
            id: "review-requests", name: "First-pass review",
            summary: "When your review is requested, an agent reads the pull request and drafts findings for you.",
            symbol: "eye", triggers: [.event(.reviewRequested)],
            action: .prompt("Review the pull request below with gh: read the description and the diff, and run the tests if that helps. Don't post anything. Reply with a one-line verdict, then concrete findings, most important first, each with its file and line.")
        ),
        AutomationTemplate(
            id: "morning-check", name: "Morning check",
            summary: "Every morning, an agent runs the tests and linters and fixes what's clearly broken.",
            symbol: "sunrise", triggers: [.schedule(.daily(hour: 9, minute: 0))],
            action: .prompt("Run the test suite and the linters. If something fails, fix what's clearly broken and commit it on this branch. Then summarize what passed, what failed, and what you changed.")
        ),
    ]
}
