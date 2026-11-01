#if DEBUG
import ACP
import Experiments
import Foundation
import NativeAutomation
import NativeSetup
import SwiftUI

/// Questions and failed starts for previews, in the shapes the agents send them.
enum AskPreviewFixtures {
    /// Two questions as Claude Code's adapter sends AskUserQuestion, the first with its suggested
    /// choice marked "(Recommended)".
    static let settingsQuestions = """
        {"type": "object", "properties": {
          "question_0": {"type": "string", "title": "Storage", "description": "Where should each turn's settings be recorded?",
            "oneOf": [
              {"const": "turn", "title": "On the turn, in SessionState (Recommended)", "description": "Survives reloads and reaches every client. Needs a store migration."},
              {"const": "defaults", "title": "In the task's saved defaults", "description": "No migration. Cleared with the conversation."},
              {"const": "none", "title": "Don't record them yet", "description": "Keep today's behavior and revisit with the transcript work."}]},
          "question_0_custom": {"type": "string", "title": "Other"},
          "question_1": {"type": "array", "title": "Shown in", "description": "Where should the transcript show them?",
            "items": {"anyOf": [{"const": "header", "title": "The turn's header"}, {"const": "well", "title": "The task well"}]}},
          "question_1_custom": {"type": "string", "title": "Other"}
        }}
        """
    /// A question that takes several choices.
    static let severalChoices = """
        {"type": "object", "properties": {
          "question_0": {"type": "array", "title": "Shown in", "description": "Where should the transcript show them?",
            "items": {"anyOf": [{"const": "header", "title": "The turn's header", "description": "Beside the time the turn ran."},
                                {"const": "well", "title": "The task well", "description": "Only for the turn that's running."}]}},
          "question_0_custom": {"type": "string", "title": "Other"}
        }}
        """
    static let freeText =
        #"{"type": "object", "properties": {"name": {"type": "string", "description": "What should the new branch be called?"}}}"#

    static let longChoices = settingsQuestions.replacingOccurrences(
        of: "Survives reloads and reaches every client. Needs a store migration.",
        with: String(
            repeating: "Keep the settings with the turn so another client can restore the same model and permissions. ",
            count: 24))

    static func questionnaire(_ schema: String = settingsQuestions) -> AgentQuestionnaire? {
        SessionModel.previewDecode(JSONValue.self, schema).flatMap {
            AgentQuestionnaire(message: "Please answer the following questions.", schema: $0)
        }
    }

    /// `picked` chooses that option of the first question.
    static func question(
        _ schema: String? = settingsQuestions, message: String = "Please answer the following questions.",
        isAvailable: Bool = true, picked: Int? = nil
    ) -> some View {
        let questionnaire = schema.flatMap(questionnaire)
        var answers = AgentQuestionnaireAnswers(suggesting: questionnaire)
        if let picked, let first = questionnaire?.questions.first, first.options.indices.contains(picked) {
            answers.pick(first.options[picked], in: first)
        }
        return ApprovalSurface {
            AnnotatedQuestionView(
                agentName: "Claude Code", questionnaire: questionnaire,
                message: message, takesFocus: false, isAvailable: isAvailable, initialAnswers: answers,
                onSubmit: { _ in }, onDecline: {})
        }
    }

    /// A Claude Code task in the middle of a turn, asking the settings questions.
    @ViewBuilder static func questionComposer() -> some View {
        let app = AppModel.preview(.empty)
        let defaults = PreviewUserDefaults()
        let modes = TaskModes(library: ModeLibrary(defaults: defaults), defaults: defaults)
        let experiments = ExperimentStore(catalog: .native, storage: InMemoryExperimentStorage())
        let _ = experiments.set(true, for: .composerNext)
        let automation = AutomationCenter(
            goalStore: GoalStore(url: URL(filePath: "/native-preview-unused/goals.json")),
            workflows: WorkflowRunner(store: nil), automations: AutomationEngine(store: nil))
        if let session = SessionModel.preview(
            in: app, agent: "claude-code", title: "Record each turn's settings", phase: .prompting)
        {
            let _ = ask(session)
            ComposerView(session: session, taskModes: modes)
                .environment(app).environment(automation).environment(CommandRegistry.shared)
                .environment(\.experimentStore, experiments)
        }
    }

    private static func ask(_ session: SessionModel) {
        session.previewRunningTurn(
            "Record the model, effort and autonomy each turn ran with. Ask me before choosing where.")
        let json = """
            {"sessionId": "\(session.id.rawValue)", "mode": "form", "message": "Please answer the following questions.",
             "requestedSchema": \(settingsQuestions)}
            """
        guard let request = SessionModel.previewDecode(CreateElicitationRequest.self, json) else { return }
        session.requestQuestion(request, id: .int(1))
    }

    // MARK: - Failed starts

    /// codex-acp 2.2.2's answer to session/new for a value it doesn't know, with this fixture's path.
    static let unknownEffort = """
        failed to load configuration: /Users/developer/.codex/config.toml:3:26: unknown variant `xhigh`, \
        expected one of `minimal`, `low`, `medium`, `high`

        Check /Users/developer/.codex and project .codex directories, especially their config.toml files, \
        or any CODEX_CONFIG override.
        """
    static let unterminated = """
        failed to load configuration: /Users/developer/.codex/config.toml:2:21: invalid basic string, expected `"`

        Check /Users/developer/.codex and project .codex directories, especially their config.toml files, \
        or any CODEX_CONFIG override.
        """
    static let configLines = [
        AgentStartDiagnostic.SourceLine(number: 2, text: "model = \"gpt-6.1-sol\"", isRedacted: false),
        AgentStartDiagnostic.SourceLine(number: 3, text: "model_reasoning_effort = \"xhigh\"", isRedacted: false),
    ]

    static func failure(
        _ output: String = unknownEffort, source: [AgentStartDiagnostic.SourceLine] = configLines,
        canFix: Bool = true, recovery: AgentStartFailureView.Recovery = .retry(restarts: false),
        draft: AgentStartFailureView.Draft = .waiting, fixFailure: String? = nil, showsOutput: Bool = false
    ) -> some View {
        let diagnostic = AgentStartDiagnostic(output: output)
        return AgentStartFailureView(
            agentName: "Codex", title: diagnostic == nil ? "Couldn't start a Codex task" : "Codex couldn't start",
            output: output, diagnostic: diagnostic,
            displayPath: diagnostic.map { $0.path.replacingOccurrences(of: "/Users/developer", with: "~") },
            source: source, fixIt: canFix && fixFailure == nil ? diagnostic?.fixIt : nil, recovery: recovery,
            draft: draft,
            fixFailure: fixFailure, initiallyShowsOutput: showsOutput, onRecover: {}, onFix: {})
    }
}
#endif
