import Foundation

/// The workflows Native ships. Written in the same JSON plugins use, so they double as the format's
/// reference. Agents are chosen relative to each other, never by name, so every workflow crosses
/// providers when the user has more than one agent and still runs when they have one.
public nonisolated enum BuiltInWorkflows {
    public static let all: [WorkflowDefinition] = sources.compactMap { source in
        try? JSONDecoder().decode(WorkflowDefinition.self, from: Data(source.utf8))
    }

    // Shared prompt text, spliced into the JSON below.
    private static let planPrompt =
        #"Plan this change in {{project}} ({{cwd}}). Don't edit any files.\n\n{{input}}\n\nRead the relevant code first. Then write a plan someone could follow without asking questions: the approach and why, the files to change and what changes in each, edge cases, and how to verify the result, including the tests to add or run. Keep it concrete and no longer than it needs to be."#

    private static let reviewPrompt =
        #"Review the changes in {{project}} ({{cwd}}) that implement:\n\n{{input}}\n\n{{steps.implement.agent}} summarized the work as:\n\n{{steps.implement.output}}\n\nRead the actual changes rather than relying on the summary: `git diff` for uncommitted work, and `git log -p` for commits on this branch that aren't on the default branch. Look for bugs, missed requirements, unhandled edge cases and missing tests. Don't change anything. Start with a one-line verdict (ready, or needs changes), then list concrete findings, most important first, each with its file and line."#

    private static let addressPrompt =
        #"{{steps.review.agent}} reviewed your changes and reported:\n\n{{steps.review.output}}\n\nFix every finding you agree with and verify the fixes: it builds and the relevant tests pass. For a finding you disagree with, explain why instead. The goal is complete when every finding is fixed and verified, or answered. Finish with a short summary of what you changed."#

    public static let sources: [String] = [
        #"""
        {
          "id": "plan-implement-review",
          "name": "Plan, implement, review",
          "summary": "One agent plans, another implements the plan, and the planner reviews the result.",
          "symbol": "list.bullet.rectangle",
          "input": { "label": "What should change?", "placeholder": "Add a --json flag to the export command" },
          "steps": [
            { "id": "plan", "title": "Plan", "prompt": "\#(planPrompt)" },
            {
              "id": "implement", "title": "Implement", "agent": { "differentFrom": "plan" },
              "approval": "Check the plan before implementation starts. Edit the prompt to adjust it.",
              "goal": { "maxIterations": 8 },
              "prompt": "Implement this change in {{project}} ({{cwd}}):\n\n{{input}}\n\nFollow this plan, and adapt it where the code proves it wrong:\n\n{{steps.plan.output}}\n\nThe goal is complete when the change is implemented and verified: it builds and the relevant tests pass. Finish with a short summary of what you changed and how you verified it."
            },
            { "id": "review", "title": "Review", "agent": { "sameAs": "plan" }, "prompt": "\#(reviewPrompt)" }
          ]
        }
        """#,
        #"""
        {
          "id": "implement-cross-review",
          "name": "Second opinion",
          "summary": "Your agent implements it, another provider reviews the work, and the implementer fixes what it finds.",
          "symbol": "person.2.badge.gearshape",
          "input": { "label": "What should change?", "placeholder": "Fix the race in the upload retry logic" },
          "steps": [
            {
              "id": "implement", "title": "Implement", "goal": { "maxIterations": 8 },
              "prompt": "Implement this in {{project}} ({{cwd}}):\n\n{{input}}\n\nThe goal is complete when it's implemented and verified: it builds and the relevant tests pass, with tests added where they're missing. Finish with a short summary of what you changed and how you verified it."
            },
            { "id": "review", "title": "Cross-review", "agent": { "differentFrom": "implement" }, "prompt": "\#(reviewPrompt)" },
            {
              "id": "address", "title": "Address review", "continues": "implement",
              "approval": "Check the review before the implementer acts on it. Skip this step if nothing needs fixing.",
              "goal": { "maxIterations": 5 },
              "prompt": "\#(addressPrompt)"
            }
          ]
        }
        """#,
        #"""
        {
          "id": "ship-pull-request",
          "name": "Ship a pull request",
          "summary": "Plan, implement on a branch, cross-review, fix what the review finds, then open a pull request.",
          "symbol": "arrow.triangle.pull",
          "input": { "label": "What should the pull request do?", "placeholder": "Let users export reports as CSV" },
          "steps": [
            { "id": "plan", "title": "Plan", "prompt": "\#(planPrompt)" },
            {
              "id": "implement", "title": "Implement", "agent": { "differentFrom": "plan" },
              "approval": "Check the plan before implementation starts. Edit the prompt to adjust it.",
              "goal": { "maxIterations": 10 },
              "prompt": "Implement this change in {{project}} ({{cwd}}):\n\n{{input}}\n\nFollow this plan, and adapt it where the code proves it wrong:\n\n{{steps.plan.output}}\n\nWork on a branch of its own: if you're on the default branch, create one named for the change. Commit your work with clear messages once it's verified, and don't push. The goal is complete when the change is committed and verified: it builds and the relevant tests pass. Finish with a summary of the change written for a pull request description: what changed, why, and how it was tested."
            },
            { "id": "review", "title": "Cross-review", "agent": { "differentFrom": "implement" }, "prompt": "\#(reviewPrompt)" },
            {
              "id": "address", "title": "Address review", "continues": "implement",
              "goal": { "maxIterations": 5 },
              "prompt": "\#(addressPrompt) Commit the fixes; don't push."
            },
            {
              "id": "pull-request", "title": "Open pull request", "kind": "pullRequest",
              "approval": "Open the pull request? Edit its description first if you like.",
              "pullRequest": {
                "title": "{{title}}",
                "body": "{{steps.implement.output}}\n\n---\nPlanned, implemented and cross-reviewed ({{steps.review.agent}}) with a Native workflow."
              }
            }
          ]
        }
        """#,
    ]
}
