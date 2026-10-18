import Foundation
import Testing

@testable import NativeAutomation

@Suite struct WorkflowDefinitionTests {
    @Test func builtInsDecodeAndValidate() throws {
        #expect(BuiltInWorkflows.all.count == BuiltInWorkflows.sources.count)
        for definition in BuiltInWorkflows.all {
            #expect(WorkflowIssue.find(in: definition) == [], "\(definition.id)")
        }
        let library = WorkflowLibrary()
        #expect(library.runnable.map(\.id) == ["plan-implement-review", "implement-cross-review", "ship-pull-request"])
    }

    @Test func builtInsRoundTripThroughJSON() throws {
        for definition in BuiltInWorkflows.all {
            let data = try JSONEncoder().encode(definition)
            #expect(try JSONDecoder().decode(WorkflowDefinition.self, from: data) == definition)
        }
    }

    @Test func pluginJSONShorthands() throws {
        let json = #"""
            {"id": "w", "name": "W", "steps": [
              {"id": "a", "prompt": "Do {{input}}", "goal": true, "approval": "Check it"},
              {"id": "b", "agent": "codex", "prompt": "Review {{steps.a.output}}", "after": ["a"]},
              {"id": "c", "agent": {"differentFrom": "b"}, "prompt": "x", "approval": true, "after": []},
              {"id": "pr", "kind": "pullRequest", "pullRequest": {"body": "{{steps.a.output}}", "draft": true}, "after": ["a"]}
            ]}
            """#
        let definition = try JSONDecoder().decode(WorkflowDefinition.self, from: Data(json.utf8))
        #expect(definition.steps[0].goal == WorkflowStep.defaultGoalBudget)
        #expect(definition.steps[0].approval == WorkflowApproval(message: "Check it"))
        #expect(definition.steps[0].title == "a")
        #expect(definition.steps[1].agent == .agent("codex"))
        #expect(definition.steps[2].agent == .differentFrom("b"))
        #expect(definition.steps[2].approval == WorkflowApproval())
        #expect(definition.steps[3].pullRequest?.title == "{{title}}")
        #expect(definition.steps[3].pullRequest?.isDraft == true)
        #expect(definition.input.isRequired)
        #expect(WorkflowIssue.find(in: definition) == [])
    }

    @Test func validationCatchesBrokenReferences() {
        let definition = WorkflowDefinition(
            id: "w", name: "W", summary: "",
            steps: [
                WorkflowStep(id: "a", title: "A", prompt: "Uses {{steps.b.output}} and {{nope}}"),
                WorkflowStep(id: "b", title: "B", agent: .sameAs("c"), prompt: "x", after: ["z"]),
                WorkflowStep(id: "b", title: "Dup", continues: "a", prompt: ""),
                WorkflowStep(id: "pr", title: "PR", kind: .pullRequest),
            ])
        let messages = WorkflowIssue.find(in: definition).map(\.description)
        #expect(messages.contains("Step \"a\": It uses \"b\"'s result, but doesn't wait for that step."))
        #expect(messages.contains("Step \"a\": {{nope}} isn't a variable."))
        #expect(messages.contains("Step \"b\": \"after\" names \"z\", which isn't an earlier step."))
        #expect(messages.contains("Step \"b\": Its agent refers to \"c\", which isn't an earlier step."))
        #expect(messages.contains("Step \"b\": Another step already uses this id."))
        #expect(messages.contains("Step \"b\": The prompt is empty."))
        #expect(messages.contains("Step \"pr\": A pull request step needs \"pullRequest\" with at least a body."))
    }

    @Test func parallelContinuationsOfOneTaskAreRejected() {
        let definition = WorkflowDefinition(
            id: "w", name: "W", summary: "",
            steps: [
                WorkflowStep(id: "a", title: "A", prompt: "x"),
                WorkflowStep(id: "b", title: "B", continues: "a", prompt: "x", after: ["a"]),
                WorkflowStep(id: "c", title: "C", continues: "a", prompt: "x", after: ["a"]),
            ])
        #expect(WorkflowIssue.find(in: definition).map(\.step) == ["c"])
    }

    @Test func libraryKeepsTheFirstOfDuplicateIDs() {
        let duplicate = WorkflowDefinition(
            id: "plan-implement-review", name: "Mine", summary: "",
            steps: [WorkflowStep(id: "a", title: "A", prompt: "x")])
        let library = WorkflowLibrary(contributions: [("my-plugin", [duplicate])])
        #expect(library.entry("plan-implement-review")?.source == .builtIn)
        #expect(library.entries.last?.isRunnable == false)
        #expect(library.runnable.count == 3)
    }

    @Test func templatesRender() {
        var values = WorkflowTemplate.Values(input: "Add CSV", title: "Add CSV", cwd: URL(filePath: "/work/app"))
        values.outputs["plan"] = "1. Do it"
        values.agents["plan"] = "Claude Code"
        let text = WorkflowTemplate.render(
            "In {{ project }} ({{cwd}}): {{input}}\n{{steps.plan.output}} by {{steps.plan.agent}}; {{steps.gone.output}}",
            with: values)
        #expect(
            text
                == "In app (/work/app): Add CSV\n1. Do it by Claude Code; (No output: that step was skipped or didn't reply.)"
        )
        #expect(WorkflowTemplate.render("unclosed {{input", with: values) == "unclosed {{input")
    }

    @Test func assignmentCrossesProvidersAndFallsBack() throws {
        let claude = WorkflowAgent(id: "claude-code", name: "Claude Code")
        let codex = WorkflowAgent(id: "codex", name: "Codex")
        let definition = try #require(BuiltInWorkflows.all.first { $0.id == "plan-implement-review" })

        let both = WorkflowAssignment.resolve(definition, agents: [claude, codex], defaultAgent: "claude-code")
        #expect(both["plan"]?.agent == claude)
        #expect(both["implement"]?.agent == codex)
        #expect(both["review"]?.agent == claude)

        let codexDefault = WorkflowAssignment.resolve(definition, agents: [claude, codex], defaultAgent: "codex")
        #expect(codexDefault["plan"]?.agent == codex)
        #expect(codexDefault["implement"]?.agent == claude)

        let solo = WorkflowAssignment.resolve(definition, agents: [codex], defaultAgent: "codex")
        #expect(solo["implement"]?.agent == codex)
        #expect(solo["implement"]?.note?.contains("Only one agent") == true)

        let overridden = WorkflowAssignment.resolve(
            definition, agents: [claude, codex], defaultAgent: "claude-code", overrides: ["implement": "claude-code"])
        #expect(overridden["implement"]?.agent == claude)
    }
}
