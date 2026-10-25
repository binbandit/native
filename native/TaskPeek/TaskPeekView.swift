import ACP
import SwiftUI

/// One moment, in the place the user is already reading. Permission and question content is shared
/// with the task.
struct TaskPeekView: View {
    let request: TaskPeekPresentation.Request
    var maxBodyHeight = DS.Peek.maxBodyHeight
    @Environment(AppModel.self) private var model
    var openTask: ((SessionKey) -> Void)?
    @FocusState private var isFocused: Bool
    @State private var wantsInstructionFocus = false

    private var session: SessionModel? { request.ask?.session ?? model.session(request.task) }
    private var ask: TaskPeekAsk? {
        request.ask ?? model.taskAsks(for: request.task).first
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            SeparatorLine()
            HeightCappedScrollView(maxHeight: maxBodyHeight) {
                moment
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, showsAnnotatedApproval ? 0 : DS.Peek.bodyHorizontal)
                    .padding(.vertical, showsAnnotatedApproval ? 0 : DS.Peek.bodyVertical)
            }
        }
        .background(.dsOverlay)
        .environment(\.permissionShortcutsEnabled, false)
        .accessibilityIdentifier("task-peek")
        .focusable()
        .focused($isFocused)
        .focusedSceneValue(\.taskPeekInstructionFocus, showsInstructionEditor ? $wantsInstructionFocus : nil)
        .focusEffectDisabled()
        .onAppear {
            if case .question = ask?.content { return }
            isFocused = true
        }
        .onKeyPress(.escape) {
            model.closeTaskPeek()
            return .handled
        }
        .onKeyPress(.return) {
            // The question owns Return, including its editable answer field.
            if case .question = ask?.content { return .ignored }
            open()
            return .handled
        }
    }

    private func open() {
        if let openTask { openTask(request.task) } else { model.openPeekedTask(request.task) }
    }

    /// The shared approval already owns its insets, including the instruction field's full-width rule.
    private var showsAnnotatedApproval: Bool {
        guard model.taskIsAvailable(request.task), model.taskIsReachable(request.task),
            let ask, ask.isCurrent, model.session(ask.session.key) === ask.session,
            case .permission = ask.content
        else { return false }
        return true
    }

    private var showsInstructionEditor: Bool {
        guard showsAnnotatedApproval, case .permission(let call) = ask?.content else { return false }
        return call.permission?.options.contains(where: \.isRejection) == true
    }

    private var header: some View {
        HStack(spacing: DS.Peek.headerGap) {
            TaskSignal(status: TaskStatus(session), placement: .peek, attentionSince: ask?.since)
            if let projectID = model.catalog.lookup(request.task)?.project,
                let project = model.projects.project(projectID)
            {
                Text(project.name).font(DS.Sidebar.projectFont).foregroundStyle(.dsTextSecondary)
                Text("/").font(.dsBody).foregroundStyle(.dsTextQuaternary)
            }
            DSInlineCodeText(model.titleOfSession(request.task))
                .font(DS.Peek.titleFont).foregroundStyle(.dsTextPrimary)
                .lineLimit(1).frame(maxWidth: .infinity, alignment: .leading)
                .help(model.titleOfSession(request.task))
            if let ask {
                DSMinuteTimeline { now in
                    Text(DSFormat.compactAge(ask.since, now: now))
                        .font(DS.Sidebar.clockFont).foregroundStyle(.dsAttention)
                }
                .fixedSize()
            }
            Button {
                open()
            } label: {
                HStack(spacing: DS.Peek.openGap) {
                    Text("Open Task").font(DS.Peek.openFont)
                    Kbd("↩", compact: true)
                }
                .fixedSize()
                .padding(.leading, DS.Peek.openLeading)
                .overlay(alignment: .leading) {
                    SeparatorLine(axis: .vertical).frame(height: DS.Peek.openDividerHeight)
                }
            }
            .buttonStyle(.plain).foregroundStyle(.dsTextTertiary)
            .padding(.leading, DS.Peek.openMargin)
            .dsHitTarget(DS.Peek.headerHeight)
            .accessibilityIdentifier("peek-open-task")
        }
        .padding(.leading, DS.Peek.headerLeading)
        .padding(.trailing, DS.Peek.headerTrailing)
        .frame(minHeight: DS.Peek.headerHeight)
    }

    @ViewBuilder private var moment: some View {
        if !model.taskIsAvailable(request.task) {
            notice("This task is no longer available", detail: "It may have been deleted from another window.")
        } else if !model.taskIsReachable(request.task) {
            notice("This host is offline", detail: "The task and its ask are kept. Reconnect the host to answer.")
        } else if let ask {
            if ask.isCurrent, model.session(ask.session.key) === ask.session {
                VStack(alignment: .leading, spacing: DS.Space.lg) {
                    answer(ask).id(ask.id).disabled(model.taskPeek.isAnswering)
                    if let failure = model.taskPeek.answerFailure {
                        ErrorState(
                            "Couldn't send your answer", recovery: "Your ask is kept. Try again.", details: failure
                        )
                        .padding(DS.Peek.bodyHorizontal)
                    }
                }
            } else {
                notice("This ask changed or was resolved", detail: "Open the task to see what happened next.")
                if !model.taskAsks(for: request.task).isEmpty {
                    Button("Show Current Ask") { model.peekTask(request.task) }.buttonStyle(.ds(.secondary))
                }
            }
        } else if let session {
            if session.phase == .loading {
                LoadingStateView("Opening the task…")
            } else if session.taskStatus == .failed {
                TaskPeekFailureView(session: session, isRecovering: model.taskPeek.isRecovering) {
                    Task { await model.recoverPeekedTask(request.task) }
                }
            } else {
                notice(session.taskStatus.label, detail: latestMessage(in: session))
            }
        } else if let failure = model.openFailures[request.task] {
            SessionOpenFailureView(
                failure: failure, onRetry: { Task { await model.loadSession(request.task) } },
                onGoBack: model.closeTaskPeek)
        } else if let runtime = model.runtime(request.task.agent), runtime.status.canRetry {
            notice("Couldn't open the task", detail: runtime.status.guidance ?? runtime.status.label)
            Button("Try Again") {
                Task {
                    await model.restart(request.task.agent, preservingDrafts: true)
                    await model.loadSession(request.task)
                }
            }
            .buttonStyle(.ds(.primary))
        } else {
            LoadingStateView("Opening the task…")
        }
    }

    @ViewBuilder private func answer(_ ask: TaskPeekAsk) -> some View {
        switch ask.content {
        case .permission(let call):
            AnnotatedApprovalView(
                call: call, agentName: ask.session.agentName, workingDirectory: ask.session.cwd.path,
                homeDirectory: model.device(of: ask.task) == .thisMac ? NSHomeDirectory() : nil,
                knowledge: model.plugins.commandKnowledge,
                responseAttempt: model.taskPeek.approvalAttempt,
                focusRequested: wantsInstructionFocus, didFocus: { wantsInstructionFocus = false },
                planEntries: call.kind == .switchMode ? ask.session.state.currentTurnPlan : [],
                planExpanded: true,
                onChoose: { option in Task { await model.answerTaskAsk(ask, option: option) } },
                onInstruct: { try await model.instructTaskAsk(ask, text: $0) }
            )
            .id(call)
        case .question(let question):
            if let schema = question.request.requestedSchema,
                let questionnaire = AgentQuestionnaire(message: question.request.message, schema: schema)
            {
                AgentQuestionSection(
                    questionnaire: questionnaire, takesFocus: true, answersHighlightedOption: true,
                    onSubmit: { content in Task { await model.answerTaskQuestion(ask, content: content) } },
                    onSkipAll: { Task { await model.answerTaskQuestion(ask, content: nil) } })
            } else {
                AgentConfirmationRow(
                    message: question.request.message,
                    onContinue: { Task { await model.answerTaskQuestion(ask, content: [:]) } },
                    onSkip: { Task { await model.answerTaskQuestion(ask, content: nil) } })
            }
        }
    }

    private func notice(_ title: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: DS.Space.md) {
            Text(title).font(.dsCalloutMedium).foregroundStyle(.dsTextPrimary)
            Text(detail).font(.dsBody).foregroundStyle(.dsTextSecondary)
                .fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
        }
    }

    private func latestMessage(in session: SessionModel) -> String {
        session.state.items.reversed().compactMap { item -> String? in
            guard case .message(let message) = item, message.role == .agent, !message.text.isEmpty else { return nil }
            return message.text
        }.first ?? "No answer yet. Open the task to see its conversation."
    }
}

extension FocusedValues {
    @Entry var taskPeekInstructionFocus: Binding<Bool>?
}

#if DEBUG
#Preview("Peek - Routine approval") { TaskPeekPreviewFixtures.view(.routine) }
#Preview("Peek - Destructive approval") { TaskPeekPreviewFixtures.view(.destructive) }
#Preview("Peek - Question") { TaskPeekPreviewFixtures.view(.question) }
#Preview("Peek - Answer delivery failed") { TaskPeekPreviewFixtures.view(.answerFailure) }
#Preview("Peek - Failure") { TaskPeekPreviewFixtures.view(.failure) }
#Preview("Peek - Recovering") { TaskPeekPreviewFixtures.view(.recovering) }
#Preview("Peek - Plan") { TaskPeekPreviewFixtures.view(.plan) }
#Preview("Peek - Finished") { TaskPeekPreviewFixtures.view(.finished) }
#Preview("Peek - Resolved") { TaskPeekPreviewFixtures.view(.resolved) }
#Preview("Peek - Loading") { TaskPeekPreviewFixtures.view(.loading) }
#Preview("Peek - Missing task") { TaskPeekPreviewFixtures.view(.missing) }
#Preview("Peek - Long command, narrow") { TaskPeekPreviewFixtures.view(.long, width: 360) }
#endif
